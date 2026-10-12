import {
  ForbiddenException,
  ServiceUnavailableException,
  UnauthorizedException,
  BadRequestException,
} from '@nestjs/common';
import * as argon2 from 'argon2';

import { AuthUser } from '../../common/decorators/current-user.decorator';
import { ResetService } from './reset.service';

jest.mock('argon2', () => ({
  verify: jest.fn(),
  hash: jest.fn(async () => 'hashed'),
}));

/// The reset is the one button that can erase a company's books, so the tests
/// are mostly about the ways it must refuse: the wrong person, the wrong
/// password, an unconfirmed request, a backup that did not work, and a second
/// press while the first is still running.
describe('ResetService', () => {
  const COMPANY_ID = '11111111-1111-4111-8111-111111111111';
  const USER_ID = '22222222-2222-4222-8222-222222222222';

  let deletions: string[];
  let companyUpdates: unknown[];
  let auditRecords: Array<Record<string, unknown>>;
  let failOn: string | null;

  /// The models the reset clears, and the order it clears them in.
  const MODELS = [
    'journalEntry',
    'salesInvoice',
    'purchaseInvoice',
    'stockMovement',
    'stockBalance',
    'documentSequence',
    'fiscalPeriod',
    'item',
    'customer',
    'supplier',
    'account',
    'auditLog',
    'userRole',
    'role',
    'user',
    'branch',
  ] as const;

  function transaction() {
    const tx: Record<string, unknown> = {
      $queryRaw: async () => [{ id: 'x' }],
      $executeRaw: async () => 1,
      company: {
        update: async (args: unknown) => {
          companyUpdates.push(args);
          return { id: COMPANY_ID };
        },
      },
    };
    for (const model of MODELS) {
      tx[model] = {
        deleteMany: async () => {
          if (failOn === model) throw new Error(`${model} failed`);
          deletions.push(model);
          return { count: 1 };
        },
      };
    }
    return tx;
  }

  function prisma(user: {
    isSuperAdmin?: boolean;
    isActive?: boolean;
    companyDeletedAt?: Date | null;
  }) {
    const tx = transaction();
    return {
      user: {
        findFirst: async () =>
          user === null
            ? null
            : {
                id: USER_ID,
                username: 'admin',
                passwordHash: 'stored-hash',
                isActive: user.isActive ?? true,
                isSuperAdmin: user.isSuperAdmin ?? true,
                companyId: COMPANY_ID,
                company: {
                  id: COMPANY_ID,
                  code: 'KAYAN',
                  deletedAt: user.companyDeletedAt ?? null,
                },
              },
        count: async () => 1,
      },
      company: {
        count: async () => 1,
        findUnique: async () => ({ code: 'KAYAN', nameEn: 'Kayan', nameAr: 'كيان' }),
      },
      journalEntry: { count: async () => 3 },
      account: { count: async () => 30 },
      customer: { count: async () => 4 },
      supplier: { count: async () => 2 },
      item: { count: async () => 5 },
      salesInvoice: { count: async () => 6 },
      purchaseInvoice: { count: async () => 2 },
      stockMovement: { count: async () => 7 },
      fiscalPeriod: { count: async () => 1 },
      branch: { count: async () => 1 },
      $transaction: async (work: (t: unknown) => Promise<unknown>) =>
        work(tx),
    };
  }

  const audit = { record: async (input: never) => void auditRecords.push({ ...(input as unknown as Record<string, unknown>) }) };

  function maintenance() {
    const state = { active: false, detail: null as string | null };
    return {
      get isActive() {
        return state.active;
      },
      begin(detail: string) {
        state.active = true;
        state.detail = detail;
      },
      end() {
        state.active = false;
        state.detail = null;
      },
      get status() {
        return { maintenance: state.active, detail: state.detail, since: null };
      },
    };
  }

  /// A backup service that succeeds, unless told otherwise.
  function backups(
    mode: 'ok' | 'dump-fails' | 'verify-fails' = 'ok',
  ) {
    return {
      createFull: async () => {
        if (mode === 'dump-fails') {
          throw new ServiceUnavailableException('pg_dump is missing');
        }
        return {
          file: { name: 'kayan-full-1.dump', sizeBytes: 1024, kind: 'full' },
          durationMs: 1,
        };
      },
      verify: async () => {
        if (mode === 'verify-fails') {
          throw new ServiceUnavailableException('the archive is damaged');
        }
        return {
          name: 'kayan-full-1.dump',
          sizeBytes: 1024,
          entries: 42,
          verifiedAt: new Date().toISOString(),
          tool: '/usr/bin/pg_restore',
        };
      },
    };
  }

  function service(
    options: {
      backups?: ReturnType<typeof backups>;
      user?: Parameters<typeof prisma>[0];
    } = {},
  ) {
    return new ResetService(
      prisma(options.user ?? {}) as never,
      audit as never,
      maintenance() as never,
      (options.backups ?? backups()) as never,
    );
  }

  const admin = (overrides: Partial<AuthUser> = {}): AuthUser => ({
    userId: USER_ID,
    username: 'admin',
    companyId: COMPANY_ID,
    branchId: null,
    isSuperAdmin: true,
    permissions: ['admin.company.manage'],
    ...overrides,
  });

  beforeEach(() => {
    deletions = [];
    companyUpdates = [];
    auditRecords = [];
    failOn = null;
    jest.mocked(argon2.verify).mockReset();
    jest.mocked(argon2.verify).mockResolvedValue(true);
  });

  it('verifies the administrator password against the stored hash', async () => {
    await service().reset(admin(), 'correct horse', 'RESET');
    expect(argon2.verify).toHaveBeenCalledWith('stored-hash', 'correct horse');
  });

  it('refuses the wrong password and deletes nothing', async () => {
    jest.mocked(argon2.verify).mockResolvedValue(false);
    await expect(
      service().reset(admin(), 'wrong', 'RESET'),
    ).rejects.toThrow(UnauthorizedException);
    expect(deletions).toEqual([]);
    expect(companyUpdates).toEqual([]);
  });

  it('refuses a principal who is not an administrator', async () => {
    await expect(
      service().reset(admin({ isSuperAdmin: false }), 'pw', 'RESET'),
    ).rejects.toThrow(ForbiddenException);
    expect(deletions).toEqual([]);
  });

  it('refuses when the account behind the token is no longer a super administrator', async () => {
    await expect(
      service({ user: { isSuperAdmin: false } }).reset(
        admin(),
        'pw',
        'RESET',
      ),
    ).rejects.toThrow(UnauthorizedException);
    expect(deletions).toEqual([]);
  });

  it('refuses when the account is deactivated', async () => {
    await expect(
      service({ user: { isActive: false } }).reset(admin(), 'pw', 'RESET'),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('refuses without the typed confirmation', async () => {
    await expect(service().reset(admin(), 'pw', 'reset')).rejects.toThrow(
      BadRequestException,
    );
    await expect(service().reset(admin(), 'pw', '')).rejects.toThrow(
      BadRequestException,
    );
    expect(deletions).toEqual([]);
  });

  it('clears the company and puts it back into the first-run state', async () => {
    const result = await service().reset(admin(), 'pw', 'RESET');
    expect(result.reset).toBe(true);
    expect(result.needsSetup).toBe(true);
    expect(result.backupFile).toBe('kayan-full-1.dump');
    // Every model above is cleared, in that order.
    expect(deletions).toEqual([...MODELS]);
    // The company is marked as not set up rather than destroyed.
    expect(companyUpdates).toHaveLength(1);
    const update = companyUpdates[0] as { data: { deletedAt: Date | null } };
    expect(update.data.deletedAt).toBeInstanceOf(Date);
  });

  it('records the reset in the audit trail without the password', async () => {
    await service().reset(admin(), 'super secret', 'RESET');
    expect(auditRecords).toHaveLength(1);
    const entry = auditRecords[0]!;
    expect(entry.action).toBe('RESET');
    expect(entry.entity).toBe('company_data');
    expect(JSON.stringify(entry)).not.toContain('super secret');
    expect(JSON.stringify(entry)).toContain('kayan-full-1.dump');
  });

  it('does not reset when the backup cannot be taken', async () => {
    await expect(
      service({ backups: backups('dump-fails') }).reset(admin(), 'pw', 'RESET'),
    ).rejects.toThrow(ServiceUnavailableException);
    expect(deletions).toEqual([]);
    expect(companyUpdates).toEqual([]);
  });

  it('does not reset when the backup cannot be verified', async () => {
    await expect(
      service({ backups: backups('verify-fails') }).reset(
        admin(),
        'pw',
        'RESET',
      ),
    ).rejects.toThrow(ServiceUnavailableException);
    expect(deletions).toEqual([]);
    expect(companyUpdates).toEqual([]);
  });

  it('rolls the clearing back when one step fails', async () => {
    failOn = 'customer';
    await expect(service().reset(admin(), 'pw', 'RESET')).rejects.toThrow(
      'customer failed',
    );
    // Nothing after the failing step ran, and the company was never marked.
    expect(deletions).not.toContain('branch');
    expect(companyUpdates).toEqual([]);
    expect(auditRecords).toEqual([]);
  });

  it('refuses a second reset while one is still running', async () => {
    const slow = {
      createFull: async () => {
        await new Promise((resolve) => setTimeout(resolve, 30));
        return {
          file: { name: 'kayan-full-1.dump', sizeBytes: 10, kind: 'full' },
          durationMs: 1,
        };
      },
      verify: async () => ({
        name: 'kayan-full-1.dump',
        sizeBytes: 10,
        entries: 1,
        verifiedAt: new Date().toISOString(),
        tool: '/usr/bin/pg_restore',
      }),
    };
    const shared = service({ backups: slow as never });
    const first = shared.reset(admin(), 'pw', 'RESET');
    await expect(shared.reset(admin(), 'pw', 'RESET')).rejects.toThrow(
      ServiceUnavailableException,
    );
    await first;
    // And it lets go afterwards, so the next one can run.
    await expect(shared.reset(admin(), 'pw', 'RESET')).resolves.toMatchObject({
      reset: true,
    });
  });

  it('counts what a reset would remove, so the warning can name it', async () => {
    const preview = await service().preview(COMPANY_ID);
    expect(preview.companyCode).toBe('KAYAN');
    expect(preview.counts).toMatchObject({
      journalEntries: 3,
      accounts: 30,
      customers: 4,
    });
    expect(preview.confirmationWord).toBe('RESET');
    // The administrator keeping their account is not counted as a deletion.
    expect(preview.counts.users).toBe(0);
  });
});
