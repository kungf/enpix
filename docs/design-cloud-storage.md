# Enpix 云存储服务设计文档

> 状态：📋 设计阶段
> 目标：让用户无需配置 S3 即可开箱即用

## 1. 背景与动机

当前 Enpix 要求用户自行提供 S3 兼容存储的 Endpoint、Access Key、Secret Key。这对开发者和极客没问题，但普通用户：

- 不知道 S3 是什么
- 不会注册 AWS / Cloudflare R2 等服务
- 不理解 AK/SK 的安全含义

**目标：** 让普通用户 30 秒内开始使用，同时保留高级用户的自定义能力。

## 2. 产品策略

### 2.1 发布路线

| 阶段 | 版本 | 内容 | 状态 |
|------|------|------|------|
| Phase 1 | v0.1 | 自定义 S3，面向技术用户，上架 App Store / Google Play | 🚧 进行中 |
| Phase 2 | v0.2 | 云存储服务，开箱即用，面向普通用户 | 📋 本文档 |
| Phase 3 | v1.0 | 付费订阅、多设备同步、团队功能 | 📋 未来 |

### 2.2 双模式架构

首次启动时提供两种选择：

```
┌─────────────────────────────────────────────┐
│              首次启动页面                      │
│                                              │
│   ┌────────────────────────────────────┐     │
│   │     ☁️  快速开始（推荐）             │     │
│   │     用 Enpix 云服务，即开即用        │     │
│   └────────────────────────────────────┘     │
│                                              │
│   ┌────────────────────────────────────┐     │
│   │     🔧  自定义存储（高级）           │     │
│   │     配置你自己的 S3 兼容服务        │     │
│   └────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

两种模式共享同一套加密逻辑和 UI，区别仅在于存储后端的路由。

## 3. 功能清单

### 3.1 P0 — 必须有

| 功能 | 说明 |
|------|------|
| 用户注册 | 邮箱 + 密码，发送验证邮件 |
| 用户登录 | 邮箱 + 密码，JWT 令牌 |
| Apple 登录 | iOS Sign in with Apple（App Store 要求） |
| Google 登录 | Android Google Sign-In |
| 忘记密码 | 邮箱验证码重置密码 |
| 自动分配存储 | 注册后自动创建用户目录，无需配置 |
| 上传/下载 | 通过 API 中转，客户端加密后上传 |
| 文件列表 | 按时间/文件夹浏览云端文件 |
| 删除文件 | 删除云端存储的文件 |

### 3.2 P1 — 应该有

| 功能 | 说明 |
|------|------|
| 免费额度 | 每用户 5GB 免费空间 |
| 用量显示 | 已用 / 总量进度条 |
| 超额提示 | 接近或超出额度时提醒 |
| App 内购 | iOS StoreKit / Google Play Billing |
| 订阅管理 | 查看、取消订阅 |

### 3.3 P2 — 可以有

| 功能 | 说明 |
|------|------|
| 多设备同步 | 同一账号多台设备自动同步 |
| 设备管理 | 查看已登录设备，远程登出 |
| 分享链接 | 生成加密分享链接（限时、限次） |
| 回收站 | 删除后保留 30 天 |

## 4. 技术架构

### 4.1 整体架构

```
┌──────────────────────────────────────────────────────────┐
│                    Flutter App                            │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │              StorageRouter                       │     │
│  │                                                  │     │
│  │   mode == cloud ──▶ CloudStorageDatasource       │     │
│  │   mode == s3    ──▶ S3StorageDatasource          │     │
│  └─────────────────────────────────────────────────┘     │
│                       │                                  │
│          加密层（XChaCha20-Poly1305）不变                  │
└───────────────────────┬──────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │   API Gateway    │
              │   api.enpix.app  │
              └────────┬─────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │   Auth   │ │  User    │ │  File    │
    │  Service │ │  Service │ │  Service │
    └──────────┘ └──────────┘ └──────────┘
          │            │            │
          ▼            ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │  JWT /   │ │  User DB │ │  S3      │
    │  OAuth   │ │ (Postgres)│ │ Bucket  │
    └──────────┘ └──────────┘ └──────────┘
```

### 4.2 客户端改动

```
lib/
├── data/
│   ├── datasources/
│   │   ├── s3_storage_datasource.dart      # 现有：直连 S3
│   │   └── cloud_storage_datasource.dart   # 新增：通过 API 中转
│   └── repositories/
│       └── storage_repository_impl.dart    # 改造：根据模式路由
├── services/
│   ├── auth_service.dart                   # 新增：JWT 管理
│   └── token_storage.dart                  # 新增：令牌安全存储
└── presentation/
    └── screens/
        ├── onboarding_screen.dart          # 新增：首次启动选择
        ├── login_screen.dart               # 新增：登录/注册
        └── quota_screen.dart               # 新增：用量展示
```

核心思路：**StorageRepository 接口不变**，只是多了一个实现。

```dart
// 现有接口，不需要改
abstract class StorageRepository {
  Future<void> upload(String path, Uint8List data);
  Future<Uint8List> download(String path);
  Future<List<StorageObject>> list({String? prefix});
  Future<void> delete(String path);
}

// 新增实现
class CloudStorageRepository implements StorageRepository {
  final ApiClient _api;  // 通过你的后端 API
  // ...实现相同的接口
}
```

### 4.3 后端技术选型

| 组件 | 推荐方案 | 备选 |
|------|----------|------|
| **认证** | Supabase Auth | Firebase Auth |
| **数据库** | Supabase Postgres | PlanetScale / Neon |
| **对象存储** | Cloudflare R2 | Backblaze B2 |
| **API 框架** | Go (Fiber) / Rust (Axum) | Node.js (Hono) |
| **部署** | Fly.io / Railway | Cloudflare Workers |

**推荐 Supabase + R2 组合：**
- Supabase Auth 免费支持 50,000 月活
- R2 免出站流量费，存储 $0.015/GB/月
- 总成本极低，适合启动阶段

### 4.4 存储隔离策略

```
bucket/
├── user-abc123/
│   ├── files/
│   │   ├── 2024/01/photo1.enc
│   │   └── 2024/02/photo2.enc
│   └── thumbs/
│       ├── photo1_thumb.enc
│       └── photo2_thumb.enc
├── user-def456/
│   ├── files/
│   └── thumbs/
```

- 每个用户一个前缀目录
- API 层强制鉴权，用户只能访问自己的路径
- 加密逻辑不变，服务端看不到明文

### 4.5 认证流程

```
注册流程：
  用户输入邮箱/密码
       │
       ▼
  API 创建用户账号
       │
       ▼
  发送验证邮件
       │
       ▼
  用户点击验证链接
       │
       ▼
  API 在 S3 创建 user-{id}/ 目录
       │
       ▼
  返回 JWT 令牌
       │
       ▼
  App 存储令牌，进入主界面

登录流程：
  用户输入邮箱/密码（或 Apple/Google 登录）
       │
       ▼
  API 验证凭据
       │
       ▼
  签发 JWT（含 user_id, 过期时间）
       │
       ▼
  App 存储令牌
       │
       ▼
  后续请求 Header: Authorization: Bearer <jwt>
```

## 5. API 设计

### 5.1 认证

```
POST   /api/auth/register          注册
POST   /api/auth/login             登录
POST   /api/auth/refresh           刷新令牌
POST   /api/auth/forgot-password   忘记密码
POST   /api/auth/reset-password    重置密码
POST   /api/auth/oauth/apple       Apple 登录
POST   /api/auth/oauth/google      Google 登录
```

### 5.2 文件操作

```
POST   /api/files/upload           上传（multipart，加密后的数据）
GET    /api/files/:key             下载
GET    /api/files?prefix=...       列表
DELETE /api/files/:key             删除
HEAD   /api/files/:key             获取元信息
```

### 5.3 用户信息

```
GET    /api/user/me                当前用户信息
GET    /api/user/quota             用量统计
GET    /api/user/subscription      订阅状态
```

### 5.4 临时凭证（可选优化）

对于大文件，可以签发临时 S3 凭证让客户端直传：

```
POST   /api/files/presign-upload   获取上传预签名 URL
POST   /api/files/presign-download 获取下载预签名 URL
```

这样大文件不经过你的 API 服务器，节省带宽。

## 6. 安全设计

| 措施 | 说明 |
|------|------|
| 传输加密 | 全链路 HTTPS，客户端加密后再传输 |
| 密码存储 | bcrypt / argon2id 哈希 |
| JWT 有效期 | Access Token 15 分钟，Refresh Token 7 天 |
| 速率限制 | 登录 5次/分钟，上传 100次/分钟 |
| 路径校验 | API 层校验用户只能操作自己的 `user-{id}/` 路径 |
| 加密不变 | 端到端加密逻辑不变，服务端只存密文 |

## 7. 成本估算

假设 1000 活跃用户，平均每人 10GB：

| 项目 | 方案 | 月成本 |
|------|------|--------|
| 存储 (10TB) | Cloudflare R2 | ~$150 |
| 数据库 | Supabase Pro | ~$25 |
| API 服务器 | Fly.io (2x shared-cpu-1x) | ~$10 |
| 域名 + SSL | Cloudflare | 免费 |
| 邮件验证 | Resend / Postmark | ~$5 |
| **合计** | | **~$190/月** |

收入覆盖成本所需：1000 用户 × 付费率 × 月费 > $190

## 8. 实施计划

| 周期 | 任务 | 产出 |
|------|------|------|
| 第 1 周 | 后端脚手架：认证 + 用户表 | 可注册/登录 |
| 第 2 周 | 文件 API：上传/下载/列表 | 核心功能打通 |
| 第 3 周 | 客户端改造：双模式 + 登录 UI | 可切换存储模式 |
| 第 4 周 | 集成测试 + 安全审计 | 可内测 |
| 第 5-6 周 | App 内购 + 额度管理 | 可商业化 |
| 第 7-8 周 | 打磨 + 上线 | 正式发布 |

## 9. 风险与对策

| 风险 | 对策 |
|------|------|
| 用户忘密码无法恢复加密数据 | 注册时生成恢复密钥，让用户抄写保存 |
| 服务端被入侵 | 服务端只存密文，无法解密用户数据 |
| S3 费用超预期 | 设置每用户硬性额度上限 |
| App Store 审核被拒加密功能 | 提前提交 ERN 加密合规申请 |

## 10. 与当前版本的关系

```
v0.1（当前）── 纯本地 + 自定义 S3
    │
    │  上架 App Store / Google Play
    │  收集用户反馈
    │
    ▼
v0.2（本文档）── 增加云存储服务
    │
    │  代码改动最小化：
    │  - 新增 CloudStorageDatasource
    │  - 新增 Auth 相关 UI
    │  - StorageRouter 按模式切换
    │  - 加密逻辑、数据库、现有 UI 完全不动
    │
    ▼
v1.0 ── 付费 + 多设备 + 团队
```

**核心原则：** 加密逻辑和 UI 层不动，只换存储后端的接入方式。
