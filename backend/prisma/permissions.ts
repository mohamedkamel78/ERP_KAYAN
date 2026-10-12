/**
 * The permission catalogue.
 *
 * One list, shared by the development seed and the demo data builder, so the
 * two can never drift: a permission that exists in one must exist in the
 * other. Rows here are global - they belong to no company - and are safe to
 * upsert at any time.
 *
 * Each entry is [code, English name, Arabic name, module].
 */
export const PERMISSIONS: Array<[string, string, string, string]> = [
  ['accounting.accounts.read', 'View chart of accounts', 'عرض دليل الحسابات', 'accounting'],
  ['accounting.accounts.create', 'Add accounts to the chart', 'إضافة حسابات للدليل', 'accounting'],
  ['accounting.accounts.update', 'Edit accounts', 'تعديل الحسابات', 'accounting'],
  ['accounting.accounts.delete', 'Delete accounts', 'حذف الحسابات', 'accounting'],
  ['accounting.journal.read', 'View journal entries', 'عرض القيود اليومية', 'accounting'],
  ['accounting.journal.create', 'Create journal entries', 'إنشاء قيود يومية', 'accounting'],
  ['accounting.journal.post', 'Post and reverse entries', 'ترحيل وعكس القيود', 'accounting'],
  ['admin.users.manage', 'Manage users', 'إدارة المستخدمين', 'admin'],
  ['admin.roles.manage', 'Manage roles', 'إدارة الأدوار', 'admin'],
  ['admin.audit.read', 'View audit trail', 'عرض سجل التدقيق', 'admin'],
  ['admin.backup', 'Take and restore backups', 'أخذ واسترجاع نسخة احتياطية', 'admin'],
  ['admin.company.manage', 'Manage company profile and branches', 'إدارة بيانات الشركة والفروع', 'admin'],

  ['parties.customers.read', 'View customers', 'عرض العملاء', 'parties'],
  ['parties.customers.create', 'Add customers', 'إضافة عملاء', 'parties'],
  ['parties.customers.update', 'Edit customers', 'تعديل العملاء', 'parties'],
  ['parties.suppliers.read', 'View suppliers', 'عرض الموردين', 'parties'],
  ['parties.suppliers.create', 'Add suppliers', 'إضافة موردين', 'parties'],
  ['parties.suppliers.update', 'Edit suppliers', 'تعديل الموردين', 'parties'],

  ['inventory.items.read', 'View items', 'عرض الأصناف', 'inventory'],
  ['inventory.items.create', 'Add items', 'إضافة أصناف', 'inventory'],
  ['inventory.items.update', 'Edit items', 'تعديل الأصناف', 'inventory'],
  ['inventory.stock.read', 'View stock balances', 'عرض أرصدة المخزون', 'inventory'],

  ['sales.invoices.read', 'View sales invoices', 'عرض فواتير البيع', 'sales'],
  ['sales.invoices.create', 'Create sales invoices', 'إنشاء فواتير البيع', 'sales'],
  ['sales.invoices.post', 'Post and reverse sales invoices', 'ترحيل وعكس فواتير البيع', 'sales'],

  ['purchases.invoices.read', 'View purchase invoices', 'عرض فواتير الشراء', 'purchases'],
  ['purchases.invoices.create', 'Create purchase invoices', 'إنشاء فواتير الشراء', 'purchases'],
  ['purchases.invoices.post', 'Post and reverse purchase invoices', 'ترحيل وعكس فواتير الشراء', 'purchases'],

  ['reports.read', 'View reports', 'عرض التقارير', 'reports'],

  ['accounting.periods.read', 'View fiscal periods', 'عرض الفترات المالية', 'accounting'],
  ['accounting.periods.manage', 'Manage fiscal periods', 'إدارة الفترات المالية', 'accounting']
];
