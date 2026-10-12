import { BadRequestException } from '@nestjs/common';

import { BackupController } from './backup.controller';
import { BackupFile, BackupService } from './backup.service';

describe('BackupService & BackupController (Company JSON Backup)', () => {
  const COMPANY_ID = '11111111-1111-4111-8111-111111111111';
  let service: BackupService;
  let controller: BackupController;
  let prismaMock: any;
  let auditMock: any;

  beforeEach(() => {
    prismaMock = {
      company: {
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.id === COMPANY_ID || where.code === 'KAYAN') {
            return {
              id: COMPANY_ID,
              code: 'KAYAN',
              nameAr: 'شركة كيان',
              nameEn: 'Kayan Company',
            };
          }
          return null;
        }),
      },
      branch: {
        findMany: jest.fn(async () => []),
        deleteMany: jest.fn(async () => ({ count: 0 })),
        createMany: jest.fn(async () => ({ count: 0 })),
        updateMany: jest.fn(async () => ({ count: 0 })),
      },
      account: {
        findMany: jest.fn(async () => []),
        deleteMany: jest.fn(async () => ({ count: 0 })),
        createMany: jest.fn(async () => ({ count: 0 })),
        updateMany: jest.fn(async () => ({ count: 0 })),
      },
      $transaction: jest.fn(async (callback: any) => {
        return callback();
      }),
    };

    // Populate all other tables with mocked findMany, deleteMany, createMany
    const models = [
      'role',
      'rolePermission',
      'user',
      'userRole',
      'userBranch',
      'fiscalPeriod',
      'customer',
      'supplier',
      'item',
      'stockBalance',
      'stockMovement',
      'journalEntry',
      'journalLine',
      'salesInvoice',
      'salesInvoiceLine',
      'purchaseInvoice',
      'purchaseInvoiceLine',
      'documentSequence',
      'auditLog',
    ];
    for (const model of models) {
      prismaMock[model] = {
        findMany: jest.fn(async () => []),
        deleteMany: jest.fn(async () => ({ count: 0 })),
        createMany: jest.fn(async () => ({ count: 0 })),
      };
    }

    auditMock = {
      record: jest.fn(async () => {}),
    };

    service = new BackupService(prismaMock, auditMock);
    controller = new BackupController(service, auditMock);
  });

  describe('Validation & Format checks', () => {
    test('rejects file that is not a kayan-backup format', async () => {
      const invalid = { format: 'other-format', version: 1 } as any;
      await expect(service.inspect(invalid, COMPANY_ID)).rejects.toThrow(
        BadRequestException,
      );
    });

    test('rejects file with future version', async () => {
      const invalid: BackupFile = {
        format: 'kayan-backup',
        version: 99,
        createdAt: new Date().toISOString(),
        companyId: COMPANY_ID,
        companyCode: 'KAYAN',
        companyName: 'Test',
        counts: {},
        tables: {},
      };
      await expect(service.inspect(invalid, COMPANY_ID)).rejects.toThrow(
        BadRequestException,
      );
    });
  });

  describe('Mutual rejection in BackupController', () => {
    test('explicitly rejects PostgreSQL DUMP (.dump / PGDMP) on JSON company restore route', () => {
      const dumpBuffer = Buffer.concat([
        Buffer.from('PGDMP'),
        Buffer.alloc(100),
      ]);
      const file = {
        originalname: 'backup.dump',
        mimetype: 'application/octet-stream',
        size: dumpBuffer.length,
        buffer: dumpBuffer,
      };

      expect(() => {
        (controller as any).parse(file);
      }).toThrow(
        /هذا الملف هو أرشيف قاعدة بيانات PostgreSQL \(\.dump\) وليس ملف نسخة احتياطية لبيانات الشركة بصيغة JSON/,
      );
    });

    test('accepts valid JSON file on company restore route', () => {
      const validJson = JSON.stringify({
        format: 'kayan-backup',
        version: 1,
        createdAt: new Date().toISOString(),
        companyId: COMPANY_ID,
        companyCode: 'KAYAN',
        companyName: 'Test',
        counts: {},
        tables: {},
      });
      const file = {
        originalname: 'company-backup.json',
        mimetype: 'application/json',
        size: validJson.length,
        buffer: Buffer.from(validJson, 'utf8'),
      };

      const parsed = (controller as any).parse(file);
      expect(parsed.format).toBe('kayan-backup');
      expect(parsed.version).toBe(1);
    });
  });

  describe('Restoring verified demo JSON backup', () => {
    test('inspects and restores demo company backup JSON cleanly', async () => {
      const backupData: BackupFile = {
        format: 'kayan-backup',
        version: 1,
        createdAt: new Date().toISOString(),
        companyId: COMPANY_ID,
        companyCode: 'KAYAN',
        companyName: 'شركة كيان للحلول والتجارة',
        counts: {
          branch: 1,
          account: 1,
          journalEntry: 1,
        },
        tables: {
          branch: [
            {
              id: '22222222-2222-4222-8222-222222222201',
              companyId: COMPANY_ID,
              code: 'MAIN',
              nameAr: 'الفرع الرئيسي',
              nameEn: 'Main Branch',
            },
          ],
          account: [
            {
              id: '66666666-6666-4666-8666-666666666601',
              companyId: COMPANY_ID,
              code: '1101',
              nameAr: 'الصندوق',
              nameEn: 'Cash',
              parentId: null,
            },
          ],
          journalEntry: [
            {
              id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01',
              companyId: COMPANY_ID,
              entryNumber: 'JE-001',
              totalDebit: '100.0000',
              totalCredit: '100.0000',
            },
          ],
        },
      };

      expect(backupData.format).toBe('kayan-backup');
      expect(backupData.version).toBe(1);
      expect(backupData.companyCode).toBe('KAYAN');
      expect(Object.keys(backupData.tables).length).toBeGreaterThan(0);

      const inspection = await service.inspect(backupData, COMPANY_ID);
      expect(inspection.format).toBe('kayan-backup');
      expect(inspection.belongsToThisCompany).toBe(true);

      const restoreResult = await service.restore(backupData, COMPANY_ID, {
        replace: true,
      });
      expect(restoreResult.companyId).toBe(COMPANY_ID);
      expect(restoreResult.total).toBeGreaterThan(0);
      expect(prismaMock.$transaction).toHaveBeenCalled();
      expect(prismaMock.account.createMany).toHaveBeenCalled();
      expect(prismaMock.branch.createMany).toHaveBeenCalled();
      expect(prismaMock.journalEntry.createMany).toHaveBeenCalled();
    });
  });
});
