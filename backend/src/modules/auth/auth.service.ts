import {
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { createHash, randomBytes } from 'node:crypto';
import { AuditService } from '../../common/audit/audit.service';
import {
  DOWNLOAD_TICKET_TYPE,
  downloadTicketTtl,
} from '../../common/download-ticket';
import { PrismaService } from '../../common/prisma/prisma.service';

const MAX_FAILED_ATTEMPTS = 5;
const LOCK_MINUTES = 15;

export interface SessionUser {
  id: string;
  username: string;
  fullName: string;
  companyId: string;
  branchId: string | null;
  roles: string[];
  permissions: string[];
  isActive: boolean;
  /// Whether this account bypasses the permission check outright. The client
  /// is told because it has to decide what to offer: a screen that hides an
  /// action the server would have allowed is as wrong as one that offers
  /// something the server will refuse.
  isSuperAdmin: boolean;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger('Auth');

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly audit: AuditService,
  ) {}

  async login(
    username: string,
    password: string,
    ip?: string,
    userAgent?: string,
  ) {
    const user = await this.prisma.user.findUnique({
      where: { username },
      include: {
        userRoles: {
          include: {
            role: { include: { rolePermissions: { include: { permission: true } } } },
          },
        },
      },
    });

    // A single generic message for every failure mode: revealing whether the
    // username exists would let an attacker enumerate accounts.
    const invalid = new UnauthorizedException('Invalid username or password');

    if (!user || user.deletedAt !== null || !user.isActive) {
      await this.audit.record({
        action: 'LOGIN_FAILED',
        entity: 'users',
        entityId: username,
        ipAddress: ip ?? null,
        userAgent: userAgent ?? null,
      });
      throw invalid;
    }

    if (user.lockedUntil && user.lockedUntil > new Date()) {
      throw new UnauthorizedException(
        'Account temporarily locked after repeated failed sign-ins',
      );
    }

    const passwordOk = await argon2.verify(user.passwordHash, password);
    if (!passwordOk) {
      const attempts = user.failedLoginCount + 1;
      await this.prisma.user.update({
        where: { id: user.id },
        data: {
          failedLoginCount: attempts,
          lockedUntil:
            attempts >= MAX_FAILED_ATTEMPTS
              ? new Date(Date.now() + LOCK_MINUTES * 60_000)
              : null,
        },
      });
      await this.audit.record({
        companyId: user.companyId,
        userId: user.id,
        action: 'LOGIN_FAILED',
        entity: 'users',
        entityId: user.id,
        ipAddress: ip ?? null,
        userAgent: userAgent ?? null,
      });
      throw invalid;
    }

    const permissions = [
      ...new Set(
        user.userRoles.flatMap((ur) =>
          ur.role.rolePermissions.map((rp) => rp.permission.code),
        ),
      ),
    ];
    const roles = [...new Set(user.userRoles.map((ur) => ur.role.code))];

    const branches = await this.prisma.userBranch.findMany({
      where: { userId: user.id },
      select: { branchId: true },
    });
    const branchId = branches[0]?.branchId ?? null;

    const accessToken = await this.jwt.signAsync(
      {
        sub: user.id,
        username: user.username,
        companyId: user.companyId,
        branchId,
        isSuperAdmin: user.isSuperAdmin,
        permissions,
      },
      {
        secret: process.env.JWT_ACCESS_SECRET,
        expiresIn: Number(process.env.JWT_ACCESS_TTL ?? 900),
      },
    );

    const refreshToken = await this.issueRefreshToken(user.id);

    await this.prisma.user.update({
      where: { id: user.id },
      data: { failedLoginCount: 0, lockedUntil: null, lastLoginAt: new Date() },
    });

    await this.audit.record({
      companyId: user.companyId,
      userId: user.id,
      action: 'LOGIN',
      entity: 'users',
      entityId: user.id,
      ipAddress: ip ?? null,
      userAgent: userAgent ?? null,
    });

    return {
      accessToken,
      refreshToken,
      user: this.toSessionUser(user, roles, permissions, branchId),
    };
  }

  /**
   * A one-minute credential for one address: a print page or a file.
   *
   * The sign-in token is what pays for it, and it is the sign-in token that
   * keeps working everywhere afterwards. What comes back here is deliberately
   * weaker — see DOWNLOAD_TICKET_TYPE for what it can and cannot do.
   */
  async issueDownloadTicket(user: {
    id: string;
    username: string;
    companyId: string;
    branchId: string | null;
    isSuperAdmin: boolean;
    permissions: string[];
  }): Promise<{ ticket: string; expiresIn: number }> {
    const expiresIn = downloadTicketTtl();
    const ticket = await this.jwt.signAsync(
      {
        typ: DOWNLOAD_TICKET_TYPE,
        sub: user.id,
        username: user.username,
        companyId: user.companyId,
        branchId: user.branchId,
        isSuperAdmin: user.isSuperAdmin,
        permissions: user.permissions,
      },
      { secret: process.env.JWT_ACCESS_SECRET, expiresIn },
    );
    return { ticket, expiresIn };
  }

  async refresh(token: string) {
    const hash = this.hashToken(token);
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hash },
      include: {
        user: {
          include: {
            userRoles: {
              include: {
                role: {
                  include: { rolePermissions: { include: { permission: true } } },
                },
              },
            },
            branches: true,
          },
        },
      },
    });

    if (!stored || stored.revokedAt || stored.expiresAt < new Date()) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    // Rotation: the presented token is revoked and a new one issued, so a
    // stolen token is usable at most once.
    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });

    const user = stored.user;
    const permissions = [
      ...new Set(
        user.userRoles.flatMap((ur) =>
          ur.role.rolePermissions.map((rp) => rp.permission.code),
        ),
      ),
    ];
    const roles = [...new Set(user.userRoles.map((ur) => ur.role.code))];
    const branchId = user.branches[0]?.branchId ?? null;

    const accessToken = await this.jwt.signAsync(
      {
        sub: user.id,
        username: user.username,
        companyId: user.companyId,
        branchId,
        isSuperAdmin: user.isSuperAdmin,
        permissions,
      },
      {
        secret: process.env.JWT_ACCESS_SECRET,
        expiresIn: Number(process.env.JWT_ACCESS_TTL ?? 900),
      },
    );

    return {
      accessToken,
      refreshToken: await this.issueRefreshToken(user.id),
      user: this.toSessionUser(user, roles, permissions, branchId),
    };
  }

  async logout(userId: string, refreshToken?: string): Promise<void> {
    if (refreshToken) {
      await this.prisma.refreshToken.updateMany({
        where: { userId, tokenHash: this.hashToken(refreshToken) },
        data: { revokedAt: new Date() },
      });
    } else {
      await this.prisma.refreshToken.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    }
    await this.audit.record({
      userId,
      action: 'LOGOUT',
      entity: 'users',
      entityId: userId,
    });
  }

  private async issueRefreshToken(userId: string): Promise<string> {
    const token = randomBytes(48).toString('base64url');
    const ttl = Number(process.env.JWT_REFRESH_TTL ?? 604800);
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: this.hashToken(token),
        expiresAt: new Date(Date.now() + ttl * 1000),
      },
    });
    return token;
  }

  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private toSessionUser(
    user: {
      id: string;
      username: string;
      fullNameEn: string;
      fullNameAr: string;
      companyId: string;
      isActive: boolean;
      isSuperAdmin: boolean;
    },
    roles: string[],
    permissions: string[],
    branchId: string | null,
  ): SessionUser {
    return {
      id: user.id,
      username: user.username,
      fullName: user.fullNameEn,
      companyId: user.companyId,
      branchId,
      roles,
      permissions,
      isSuperAdmin: user.isSuperAdmin,
      isActive: user.isActive,
    };
  }
}
