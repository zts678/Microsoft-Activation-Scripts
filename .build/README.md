# MAS_AIO 独立 EXE 封装

将 Microsoft Activation Scripts 的一体化批处理脚本 `MAS_AIO.cmd`（v3.7）封装为**单文件、无需任何运行环境**的原生 Windows 可执行程序 `MAS_AIO.exe`，并使用 `logo.png` 作为程序图标。

---

## 一、文件清单

```
新建文件夹\
├─ MAS_AIO.exe        最终成品（约 1.1 MB），双击即可运行，可单独拷贝分发
├─ MAS_AIO.cmd        原始 MAS 一体化批处理脚本（783 KB，v3.7）
├─ logo.png           程序图标源文件（256×256，32 位带透明通道）
├─ README.md          本说明文件
└─ _build\            构建工程（重新生成 exe 时使用，分发时不需要）
   ├─ build.ps1       一键构建脚本
   ├─ Launcher.cs     C# 启动器源码（含内嵌压缩载荷）
   ├─ app.manifest    应用程序清单（强制管理员权限）
   └─ logo.ico        构建时生成的多尺寸图标（由 logo.png 自动转换）
```

---

## 二、使用方法

1. 直接双击 **`MAS_AIO.exe`**；
2. 弹出 UAC 用户账户控制窗口时点击"是"（MAS 激活操作必须具备管理员权限）；
3. 出现 MAS 主菜单后，按数字键选择功能（HWID / Ohook / KMS 等），操作与原版 `MAS_AIO.cmd` 完全一致；
4. 命令行参数同样支持，例如：

   ```
   MAS_AIO.exe /HWID          （等效于 MAS_AIO.cmd /HWID）
   MAS_AIO.exe /Ohook
   MAS_AIO.exe /K-WindowsOffice
   ```

> 首次运行时窗口可能闪一下再重新打开，这是 MAS 脚本自身的 QuickEdit/conhost 重启逻辑，直接运行原版 .cmd 行为相同，属正常现象。

---

## 三、运行原理

`MAS_AIO.exe` 是使用 Windows 自带的 **.NET Framework 4.8 C# 编译器（csc.exe）** 编译的**真正原生 PE 程序**（非 IExpress 自解压包，也不依赖第三方软件）：

1. 构建时将 `MAS_AIO.cmd` 以 **GZip 压缩 + Base64 编码**内嵌进 exe（783 KB → 约 190 KB）；
2. 运行时启动器把脚本**按原始字节**释放到 `%LOCALAPPDATA%\MAS_AIO\MAS_AIO.cmd`；
3. 调用系统 `cmd.exe` 在当前控制台窗口中执行该脚本，并将命令行参数原样转发；
4. exe 内嵌 `requireAdministrator` 清单，双击即触发 UAC 提权。

### 针对 MAS 脚本特性做的适配

| MAS 脚本的限制 | 封装时的处理 |
| --- | --- |
| 脚本检测到自身路径包含 `%TEMP%` 会拒绝运行（防止从压缩包临时目录直接运行） | 释放目录选在 `%LOCALAPPDATA%\MAS_AIO\`（非 Temp 子目录） |
| 脚本内部硬编码引用文件名 `MAS_AIO.cmd`（如 $OEM$ 生成功能） | 释放文件名固定为 `MAS_AIO.cmd` |
| 脚本对换行符敏感（要求 CRLF、无 BOM，否则报 LF line ending 错误） | 载荷以二进制字节原样读写，SHA256 与原文件完全一致 |
| 脚本需要管理员权限，且自身含 PowerShell `runas` 提权逻辑 | exe 内嵌 `requireAdministrator` 清单，由系统直接提权 |
| 运行过程中会向自身目录释放 `clipup.exe` 等临时文件 | 释放目录可写，不污染 exe 所在位置 |

---

## 四、重新构建（一键）

当替换了新版 `MAS_AIO.cmd` 或更换了 `logo.png` 后，重新生成 exe：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\Administrator\Desktop\新建文件夹\_build\build.ps1"
```

构建流程（全自动，约数秒）：

1. 读取 `MAS_AIO.cmd` 原始字节；
2. GZip 压缩 + Base64 编码；
3. 注入 `Launcher.cs` 源码占位符；
4. 将 `logo.png` 转换为**标准多尺寸 ICO**（16/24/32/48/64/128/256 共 7 个尺寸，全部 PNG 无损编码、32 位透明通道；256 尺寸直接嵌入原图字节）；
5. 调用 `%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` 编译，输出 `MAS_AIO.exe`。

无需安装 Visual Studio、.NET SDK 或任何第三方工具——目标机器和构建机器只需有系统自带的 .NET Framework（Win10/Win11 默认内置）。

---

## 五、图标说明

- 程序图标为多分辨率 ICO：资源管理器的大图标/小图标/列表/详细信息、任务栏、标题栏等场景会自动选择最合适的尺寸；
- 256×256 大图标与 `logo.png` 字节完全一致，颜色、渐变、透明背景零损失；
- 若资源管理器仍显示旧图标，为 Windows 图标缓存所致，执行以下命令刷新（或直接注销/重启）：

  ```powershell
  taskkill /f /im explorer.exe
  del /a /q "%LOCALAPPDATA%\IconCache.db"
  del /a /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache_*.db"
  start explorer.exe
  ```

---

## 六、注意事项

- exe **未进行数字签名**，首次运行可能出现 SmartScreen 蓝色提示，点击"更多信息 → 仍要运行"即可；
- 脚本会在 `%LOCALAPPDATA%\MAS_AIO\` 目录留有释放的 `MAS_AIO.cmd` 及运行时文件（正常现象，删除不影响 exe，下次运行会自动重新释放）；
- 激活相关功能的使用请遵守当地法律法规与软件许可协议，本封装仅改变分发/启动形式，不修改 MAS 脚本本身的任何功能逻辑；
- 分发时只需拷贝 `MAS_AIO.exe` 单个文件即可，`_build` 目录、`MAS_AIO.cmd`、`logo.png` 均为构建所需，无需随 exe 分发。

---

## 七、构建验证记录

- ✅ 释放脚本与原始 `MAS_AIO.cmd` **SHA256 完全一致**（字节级无损）：
  `d60752a27bded6887c5cec88503f0f975acb5bc849673693ca7ba7c95bcb3ef4`
- ✅ exe 为有效 PE 程序，内嵌 `requireAdministrator` 提权清单；
- ✅ 图标资源含 7 个尺寸（16~256），256 尺寸与 `logo.png` 字节一致；
- ✅ 端到端冒烟测试：exe 启动 → 释放脚本 → cmd 执行 → 正常进入 MAS 主菜单。

## 八、破解启动版本检测方案：
最简单的方法：只改一处，[MAS_AIO.cmd#L357](file:///d:/project/mas3.12/MAS_AIO.cmd#L357)
```bat
set pingp=
```
改成：
```bat
set pingp=1
```
**原理**：检测循环的入口条件是 `if not defined pingp`，只要 `pingp` 有值，整个 for 循环体直接跳过 —— ping 不会执行、`old` 永远不会被置位，后面的 "outdated" 提示自然不会触发。全程零网络请求、零延迟。

其他等价方案（没有这个干净）：
| 方案 | 缺点 |
|------|------|
| `set pingp=` → `set pingp=1` | 无，仅 1 个字符 |
| `if defined old (` → `if 1==0 (` | 不阻止 ping 本身，仍会联网探测、有等待延迟 |
| 注释/删除整个检测块| 改动大 |
