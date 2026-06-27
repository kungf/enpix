# See-Photo 端到端架构

## 一、总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Flutter App (iOS)                            │
│                                                                     │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────────────────┐   │
│  │  本地 Tab  │   │  云端 Tab  │   │        设置 Tab              │   │
│  │  浏览照片  │   │ 浏览 S3   │   │  上传配置 / TTL / S3 / 安全   │   │
│  │  多选备份  │   │ 下载查看  │   │                              │   │
│  └─────┬─────┘   └─────┬─────┘   └──────────────┬───────────────┘   │
│        │               │                        │                   │
│  ┌─────┴───────────────┴────────────────────────┴───────────────┐  │
│  │                      Services Layer                           │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │  │
│  │  │  Crypto   │ │UploadSvc │ │  S3Svc   │ │  CredentialSvc   │ │  │
│  │  │ (加解密)  │ │(上传管线)│ │(S3 HTTP) │ │  (凭证加密存储)  │ │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘ │  │
│  │  ┌──────────┐ ┌──────────┐                                    │  │
│  │  │UploadTrk │ │ TTL Engine│                                    │  │
│  │  │(上传记录)│ │(自动清理)│                                    │  │
│  │  └──────────┘ └──────────┘                                    │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      Storage Layer                            │  │
│  │  ┌─────────────────┐  ┌──────────────────────────────────┐   │  │
│  │  │ iOS Keychain     │  │  photo_manager                   │   │  │
│  │  │ · KEK (包裹后)   │  │  · 读取相册                      │   │  │
│  │  │ · S3 AK/SK (加密)│  │  · 获取缩略图                    │   │  │
│  │  │ · UploadTracker  │  │  · 原始文件路径                  │   │  │
│  │  └─────────────────┘  └──────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ HTTPS
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         MinIO / S3                                   │
│                                                                     │
│  bucket/                                                            │
│  ├── {kek指纹}/files/2026/06/27/{uuid}.enc    ← 加密照片           │
│  ├── {kek指纹}/files/2026/06/27/{uuid}.enc    ← 加密视频           │
│  └── {kek指纹}/files/2026/06/26/{uuid}.enc                         │
│                                                                     │
│  每个 .enc 文件的 S3 metadata:                                      │
│    x-amz-meta-dek:   <KEK加密的DEK>                                 │
│    x-amz-meta-nonce: <加密用nonce>                                   │
│    x-amz-meta-hash:  <原文BLAKE2b哈希>                               │
│    x-amz-meta-filename: <原始文件名>                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 二、加密体系

### 密钥层级

```
用户密码 (8+位)
    │ Argon2id (64MiB, 3轮, 4线程)
    ▼
  KEK (256-bit)  ←──────── 会话期间存内存
    │                      解锁：Face ID 或密码
    ├──→ 包裹后存 Keychain（Secure Enclave 保护）
    │
    ├──→ 加密 S3 AK/SK → 存 Keychain
    │       AK/SK 明文永不落盘
    │
    └──→ 加密每文件的 DEK
            │
            ▼
          DEK (每文件随机, 256-bit)
            │ XChaCha20-Poly1305
            ▼
          加密后的文件 → S3
```

### 密钥存储位置

| 数据 | 存储 | 保护 |
|---|---|---|
| 用户密码 | 用户记忆 | 不存盘 |
| KEK 包裹体 | Keychain | Secure Enclave 硬件绑定 |
| S3 AK/SK (加密) | Keychain | KEK 加密后存储 |
| UploadTracker | Keychain | 系统级加密 |
| DEK (加密) | S3 metadata | KEK 包裹 |
| 原始文件 | 设备相册 | iOS 系统保护 |

---

## 三、上传 Pipeline

```
用户点击「备份」
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Step 1: 去重检查 (Layer 1)                             │
│  UploadTracker.isUploaded(asset.id)                     │
│  ← 读 Keychain，< 1ms，不读文件                         │
│  如果已上传 → skip                                       │
├─────────────────────────────────────────────────────────┤
│  Step 2: 读取文件                                        │
│  asset.originFile → File                                │
│  file.readAsBytes() → plaintext                         │
│  (大视频用 stream 读取)                                  │
├─────────────────────────────────────────────────────────┤
│  Step 3: 生成密钥                                        │
│  DEK = random(32 bytes)                                 │
│  nonce = random(24 bytes)                               │
├─────────────────────────────────────────────────────────┤
│  Step 4: 加密                                            │
│  hash = BLAKE2b(plaintext)        ← 完整性指纹           │
│  encrypted = XChaCha20(plaintext, DEK, nonce)            │
│  wrappedDek = XChaCha20(DEK, KEK) ← DEK 被 KEK 包裹     │
│  secureFree(DEK)                  ← 清零 DEK             │
├─────────────────────────────────────────────────────────┤
│  Step 5: 上传到 S3                                       │
│  s3Key = {指纹}/files/{日期}/{uuid}.enc                  │
│  PUT s3Key, body=encrypted, metadata={                   │
│    dek: wrappedDek,                                      │
│    nonce: nonce,                                         │
│    hash: hash,                                           │
│    filename: originalName                                │
│  }                                                       │
├─────────────────────────────────────────────────────────┤
│  Step 6: 记录完成                                        │
│  UploadTracker.markUploaded(                             │
│    assetId: asset.id,                                    │
│    s3Key: s3Key,                                         │
│    fileName: name,                                       │
│    contentHash: hash                                     │
│  )                                                       │
│  → 写 Keychain                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 四、下载 Pipeline

```
用户点击云端照片
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Step 1: 获取加密文件                                     │
│  GET s3Key → encrypted blob + metadata                   │
│  读 x-amz-meta-{dek, nonce, hash}                        │
├─────────────────────────────────────────────────────────┤
│  Step 2: 解出 DEK                                        │
│  wrappedDek = decode(metadata.dek)                       │
│  DEK = XChaCha20-decrypt(wrappedDek, KEK)                │
│  ← 需要 KEK 在内存（会话已解锁）                          │
├─────────────────────────────────────────────────────────┤
│  Step 3: 解密文件                                         │
│  plaintext = XChaCha20-decrypt(encrypted, DEK, nonce)    │
│  secureFree(DEK)                                         │
├─────────────────────────────────────────────────────────┤
│  Step 4: 完整性验证                                       │
│  actualHash = BLAKE2b(plaintext)                         │
│  比较 actualHash vs metadata.hash                         │
│  不匹配 → 文件损坏/被篡改 → 报错                           │
├─────────────────────────────────────────────────────────┤
│  Step 5: 显示                                             │
│  照片 → Image.memory(plaintext)                          │
│  视频 → 写临时文件 → video_player                        │
└─────────────────────────────────────────────────────────┘
```

---

## 五、TTL 引擎

### 配置模型

```
设置页
├── 📤 上传配置
│   ├── 上传阈值: 仅上传拍摄于 N 天/小时前的照片 (0=不限)
│   └── 仅 WiFi 上传
│
└── 🗑 本地清理 (TTL)
    ├── 按时间: 删除 N 天前且已上传的本地文件
    └── 按空间: 本地已上传文件超 N GB 时，删最旧的 (每次1GiB)
```

### 执行流程

```
定时任务 (workmanager, 每15分钟)
      │
      ▼
┌──────────────────────────────────────────────┐
│  Phase 1: 上传                                │
│  查询: 拍摄于 N 天前 + 未上传 + 有网络        │
│  逐个: encrypt → upload → track              │
├──────────────────────────────────────────────┤
│  Phase 2: TTL 清理 (只删已上传的)              │
│                                               │
│  时间清理:                                     │
│    SELECT 已上传 + created_at < (now - N天)    │
│    → 删除本地文件                              │
│                                               │
│  空间清理:                                     │
│    IF SUM(已上传本地文件) > N GB:              │
│      按 created_at ASC 排序                    │
│      逐个删除直到释放 1 GiB                     │
└──────────────────────────────────────────────┘
```

---

## 六、数据流图

```
                    ┌──────────────────┐
                    │   用户设置密码     │
                    └────────┬─────────┘
                             │
              ┌──────────────┴──────────────┐
              │      Argon2id 派生 KEK       │
              │      KEK 包裹后存 Keychain   │
              └──────────────┬──────────────┘
                             │
              ┌──────────────┴──────────────┐
              │     解锁会话 (Face ID/密码)   │
              │     KEK 加载到内存            │
              └──────────────┬──────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐        ┌─────────┐        ┌──────────┐
    │ 保存     │        │  上传    │        │  下载     │
    │ S3凭证   │        │  照片    │        │  照片     │
    └────┬────┘        └────┬────┘        └────┬─────┘
         │                  │                  │
         ▼                  ▼                  ▼
    AK/SK 用         读文件→加密          GET S3→解密
    KEK 加密         →上传S3             →验完整性
    →Keychain        →Tracker           →显示
```

---

## 七、组件交互

```
LocalGalleryScreen
    │
    ├── PhotoManager ── 读取系统相册 (缩略图 + 原文件)
    │
    ├── UploadTracker ── Keychain 读写 (去重)
    │
    ├── UploadService ── encrypt + upload
    │       ├── CryptoService ── XChaCha20 + BLAKE2b
    │       ├── CredentialService ── KEK 管理
    │       └── S3Service ── Dio HTTP → MinIO
    │
    └── CredentialService
            ├── FlutterSecureStorage ── iOS Keychain
            └── CryptoService ── Argon2id 派生 KEK

SettingsScreen
    │
    ├── CredentialService ── 设置密码/解锁/加密凭证
    ├── S3Service ── 测试连接
    └── CryptoService ── KEK 指纹显示
```

---

## 八、当前实现状态

| 模块 | 完成度 | 说明 |
|---|---|---|
| 本地照片浏览 | ✅ 已实现 | 按天分组、缩放查看、多选 |
| 密码/凭证管理 | ✅ 已实现 | Plan C 加密方案、Keychain 存储 |
| 加密上传 | ✅ 已实现 | 端到端加密 + S3 上传 |
| 上传追踪 | ✅ 已实现 | assetId 去重、Keychain 持久化 |
| 云端浏览 | 🔲 待实现 | 浏览 S3 文件列表、下载解密查看 |
| TTL 上传引擎 | 🔲 待实现 | workmanager 定时任务 |
| TTL 清理引擎 | 🔲 待实现 | 按时间/空间删除本地 |
| 视频支持 | 🔲 待实现 | 流式加密 + 分片上传 |
| 下载回本地 | 🔲 待实现 | 从云端恢复到本地 |
| Android | 🔲 待实现 | Android Keystore 适配 |
| 桌面端 | 🔲 待实现 | macOS/Windows/Linux |

---

## 九、S3 路径规范

```
/{bucket}/{kek指纹前12位}/
  files/
    {yyyy}/{mm}/{dd}/
      {uuid_v7}.enc          ← 加密照片/视频
  thumbs/
    {uuid_v7}.enc            ← 加密缩略图 (可选)

每个 .enc 的 S3 Object Metadata:
  x-amz-meta-dek:      base64(wrapped_DEK)     ← KEK加密的DEK
  x-amz-meta-nonce:    base64(nonce)            ← 加密随机数
  x-amz-meta-hash:     base64(BLAKE2b_plaintext) ← 原文哈希
  x-amz-meta-filename: 原始文件名
  Content-Type:        image/jpeg | video/mp4 | ...
```

---

## 十、安全边界

```
┌───────────────── 你的控制范围 ─────────────────┐
│                                                │
│  iPhone ✋                                       │
│  ├── 加密密码 (只有你知道)                       │
│  ├── S3 凭证 (只有你有)                          │
│  └── KEK 在 Secure Enclave 保护下                │
│                                                │
├────────────────────────────────────────────────┤
│                                                │
│  MinIO/S3 👁 (看不到明文)                        │
│  └── 只有加密后的 .enc 文件                     │
│                                                │
└────────────────────────────────────────────────┘

S3 能看到的信息:
  ✅ 加密文件的个数
  ✅ 加密文件的大小 (可以由此推测是照片还是视频)
  ✅ 上传时间
  ❌ 文件内容 (XChaCha20-Poly1305 加密)
  ❌ 文件名 (UUID)
  ❌ 密码或密钥 (从不传输)
```

S3 完全看不到：谁在上传、什么内容、什么文件名、用的什么密码。
