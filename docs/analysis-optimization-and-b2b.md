# Enpix 系统优化建议与 B 端化改造分析

> 状态：📋 分析建议
> 依据：v0.1 代码库实际核查（2026-08-31）
> 关联文档：[design-cloud-storage.md](design-cloud-storage.md)（C 端托管云路线）

本文档分两部分：

1. **技术优化建议**——基于代码核查发现的实际问题，按优先级排列
2. **B 端化改造**——面向企业/团队用户所需的能力建设

---

## 一、技术优化建议

### P0 — 正确性问题（现存 bug / 功能缺失）

| 问题 | 证据 | 建议 |
|---|---|---|
| WiFi-only 设置未生效 | `lib/services/settings/upload_settings.dart` 有 `wifiOnly` 字段且默认 `true`，但全 `lib/` 无任何 `connectivity` 引用，`connectivity_plus` 依赖未使用 | 上传前经 `connectivity_plus` 检查当前网络类型，WiFi-only 开启且处于蜂窝网络时暂停备份 |
| 无重试机制 | `lib/services/upload/upload_service.dart` 无 retry 逻辑 | 单文件失败指数退避重试（如 3 次），整批失败记录待续传；移动网络抖动下是刚需 |
| 大视频单 PUT 上传 | `lib/services/storage/s3_service.dart` 无 multipart，单个 300s `receiveTimeout` | 大文件走 S3 Multipart Upload（分片 8–16MB）+ 断点续传；否则 4K 视频几乎必失败 |
| 后台上传是空壳 | `lib/services/background/` 目录为空，`workmanager` / `flutter_background_service` 依赖声明未使用 | App 退后台上传即中断；实现 iOS BGTask / Android WorkManager 后台备份 |

### P0 — 安全取舍需明示

- **`saved_passphrase` 存于 Keychain 做自动解锁**（`credential_service.dart`）。这削弱了 E2E 威胁模型——拿到解锁手机（或越狱/root 设备）的人可读 Keychain，等于拿到 KEK。建议：
  - 默认**不保存口令**，自动解锁改为显式开关并附风险文案
  - 启用生物识别门禁（`local_auth` 已在依赖中，但 `lib/services/biometric/` 为空）：Keychain item 加 `access_control: biometryAny`，iOS 原生支持
- **App 进后台时未清理 session KEK**。`endSession()` 存在但无生命周期钩子调用 → 监听 `AppLifecycleState.paused`，后台 N 分钟后清零内存密钥
- `has_passphrase` 等布尔标记无需走 Keychain，普通存储即可，减少 Keychain 读写

### P1 — 可扩展性

- **UploadTracker 将全部上传记录塞进单个 Keychain JSON blob**（`upload_tracker.dart`，上限 1 万条 / 180 天）。1 万条约数百 KB，每次增删全量读写——Keychain 不适合高频率大 blob，且 1 万条对多年用户不够。上传记录**非机密**，应迁至 SQLite（drift/sqflite）或普通文件；Keychain 只保留密钥与 AK/SK
- **云相册浏览**依赖 S3 LIST 全量拉取，照片量大后会慢。建议本地维护加密 manifest（单文件缓存 + 增量刷新）
- 清理空目录脚手架：`data/database/dao`、`domain/repositories`、`data/datasources` 等空壳目录要么填充要么删除，避免误导

### P1 — 架构与代码健康

- `local_gallery_screen.dart`（1068 行）、`overview_screen.dart`（743 行）超出 800 行约定 → grid / viewer / action bar 拆分为独立 widgets
- 手写 SigV4 目前有 `sigv4_canonical_query_test` 保护，建议：canonical request 构造单独抽离 + 引入 AWS 官方测试向量集做参数化测试（各家 S3 兼容实现的签名细节差异是未来的坑）
- 测试缺口：**BackupManager、S3Service HTTP 层无测试**——备份链路恰是最不该出错的部分（现有 30 个测试文件已覆盖 crypto / ttl / tracker / 部分 widget）

---

## 二、B 端化改造

当前产品定位是"技术极客自托管"（v0.1），roadmap 的 v0.2/v1.0 是 C 端路线（免配置 + 订阅）。**B 端是第三条路线**——B 端买的不是"相册"，而是"可管控的照片资产归档"。

典型场景：房产中介房源照片、保险查勘取证、工程现场影像、电商素材库。

### 1. 必须从零建设的能力

| 能力 | 说明 |
|---|---|
| 服务端 | 当前 App 直连 S3、无后端。B 端必须有管理面：组织/成员/设备 API、策略下发、审计。工作量最大 |
| 组织模型 | 组织 → 团队 → 成员；角色至少 admin / member / viewer 三级；设备绑定成员 |
| Admin Console（Web） | 成员管理、设备管理、远程登出/擦除、用量看板、策略配置 |

### 2. 加密体系改造（B 端核心矛盾）

- **密钥托管（escrow）**：恢复密钥目前只在员工个人手里——员工离职/丢失助记词，公司数据永久丢失。必须引入**组织级恢复能力**：主密钥 Shamir 分片托管给多名管理员，或企业 KMS 托管 wrapped key。这会使"零知识"变为"半信任"模型，需如实写入白皮书并在销售时讲清
- **共享 vault**：团队成员访问同一批照片 → 引入"团队密钥"，成员各自包裹一份；当前单用户 KEK 模型不支持
- **强制策略下发**：口令复杂度、是否允许保存口令、TTL 策略由 admin 统一管控，员工不可自行修改

### 3. 合规与审计

- 操作审计日志（谁上传/下载/删除了什么、哪台设备），日志本身需防篡改
- 数据保留策略 + 法律保全（legal hold）
- 国内客户：等保二/三级、个保法（照片含人脸 = 敏感个人信息）、数据出境评估
- 出海客户：GDPR 删除权——E2E 加密下"彻底删除"反而易做（删密钥即销毁），可作为卖点
- 私有化/专有云部署：直连任意 S3 恰是现有优势，包装为"支持企业自有对象存储（MinIO / Ceph / 阿里 OSS）"

### 4. 协作功能（B 端付费点）

- 相册共享、标签、批注、检索——**加密下的搜索是硬问题**。务实方案：客户端生成加密元数据索引（日期/地点/标签）上传，服务端只做密文索引的键值查询
- 外部分享：加密分享链接 + 密码 + 有效期（roadmap v1.0 已有，B 端需提前）
- 回收站 + 版本保留（防误删/防勒索，B 端强需求）

### 5. 商业化配套

- 授权机制：按席位/按存储量订阅；私有化场景提供离线 license 文件
- 用量配额与告警、多 bucket / 多项目空间隔离
- 批量迁移工具：从 NAS / Google Photos / 微信文件批量导入

### 6. 落地顺序建议

1. **先清 P0 技术债**（重试、multipart、后台上传、WiFi 开关）——B 端客户验收会拿大文件和弱网环境测试
2. 账号体系 + 最小 Admin Console（成员/设备/远程擦除）→ 可开始 POC 销售
3. 组织级密钥恢复 + 审计日志 → 达到"企业可采购"门槛
4. 协作与搜索 → 续费/增购的理由

---

## 结论

现有的加密地基（Argon2id + XChaCha20-Poly1305 + 恢复密钥）对 B 端是加分项，但"纯客户端、无账号、无管控"的架构决定了 **B 端化 ≈ 新增一个服务端 + 重做密钥模型的多用户部分**，主要工作量在客户端之外。

若目标是普通 C 端用户，则走 [design-cloud-storage.md](design-cloud-storage.md) 的托管云路线，最高优先级是"别让普通人理解什么是 S3 Endpoint"。
