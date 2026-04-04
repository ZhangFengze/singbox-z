# singbox-z 单仓库架构说明 (基于 v1.14.0-alpha.8)

## 架构概述

本项目采用极简的 **单仓库 (Monorepo)** 架构，旨在彻底解决依赖 `sing-box` 与 `sing-tun` 的 `Fork` 带来的严重合并冲突问题。

在 Go 的层面，我们使用了原生的 `go.mod replace` 语法，这意味着在源代码层面不需要做任何全局搜索、替换导入路径 (`github.com/sagernet/sing-tun`) 的脏操作。

## 目录结构

```text
/root/singbox-z/
  ├── .github/                             <-- 自动化打包发版 CI
  │   └── workflows/
  │       └── release-openwrt-x86_64.yml   
  ├── sing-box/                            <-- 官方纯净版源码
  │   └── go.mod                           <-- 包含 replace 指令
  ├── sing-tun/                            <-- 包含自定义修补的库源码
  │   └── redirect_nftables_rules_openwrt.go <-- 修改点：fw4 接口精准放行
  ├── sing-box-auto-redirect-fw4.md        <-- 放行功能的设计草案及说明
  └── singbox-z-architecture-v1.14.0-alpha.8.md <-- 本文档
```

## 核心修改：`fw4` 动态端口网卡级放行补丁

我们在 `./sing-tun/redirect_nftables_rules_openwrt.go` 中植入了一个极其关键的安全补丁。

**解决了什么问题？**
在 OpenWrt (fw4 / nftables 环境) 运行带有 `auto_redirect` 特性的 `sing-box` 时，如果流量被重新路由到了一个动态端口上，防火墙默认是拦截的，导致流量丢失。

**补丁内容：**
自动解析 `auto_redirect` 所生成的临时端口，并在向系统写入防火墙配置 `/etc/nftables.d/0-sing-box-auto-redirect.nft` 时，附加上一条专用的放行规则。

**安全性：**
补丁并不是盲目放行全局流量，它读取了你的 `sing-box` 配置文件中的 `include_interface` 和 `exclude_interface` 设置，生成的 nftables 放行规则会自动带有严格的 `iifname`（进入网卡名）判定。例如，你的内网流量来自于 `br-lan`，它就只放行从 `br-lan` 进入到此动态端口的流量，严格屏蔽了 `wan` 口等外部扫描，彻底避免了公网暴露风险。

## 为什么这种结构最好？（未来的极简更新方式）

以后当你需要升级版本时，你**再也不需要去处理 Git 树上的合并冲突了**。

### 升级 `sing-box` (如升级到 v1.15.0)

1. 把旧的 `sing-box/` 文件夹**直接删掉**。
2. 从官方拉一份最新的纯净版源码塞进来：
   ```bash
   git clone -b v1.15.0 --depth 1 https://github.com/SagerNet/sing-box.git sing-box
   # 注意：只需删除 .git 和官方的 workflows 即可，切勿删除整个 .github，否则出包时会找不到编译所需的环境版本号和打包脚本！
   rm -rf sing-box/.git sing-box/.github/workflows
   ```
3. 在新的 `sing-box/go.mod` 最底部加回这行金句：
   ```go
   replace github.com/sagernet/sing-tun => ../sing-tun
   ```

### 升级 `sing-tun`

如果新版本要求升级底层的 `sing-tun`，操作也是一样的：

1. 看一眼新版 `go.mod` 里 `sing-tun` 的版本 Commit 号（例如 `abcdef`）。
2. 把旧的 `sing-tun/` 文件夹**直接删掉**。
3. 从官方拉一份这个版本号的源码：
   ```bash
   git clone https://github.com/SagerNet/sing-tun.git sing-tun
   cd sing-tun && git checkout abcdef && rm -rf .git
   ```
4. 打开 `sing-tun/redirect_nftables_rules_openwrt.go`，把你的 `fw4` 放行补丁代码贴回去即可（可以直接照抄本仓库老代码，只需改这一个文件）。

## 自动化出包 (GitHub Action)

我们在项目根目录保留了 `.github/workflows/release-openwrt-x86_64.yml`。
它监听 `main` 分支的提交。只要你修改了代码然后 `git push`，它就会：
1. 自动去云端拉取交叉编译链（Chromium toolchain, cronet 等）。
2. 调用带有我们 `replace` 指令的新结构，编译出最新的 `sing-box`。
3. 使用 Action 触发时的运行次数（`github.run_number`）生成合规的版本号，然后直接发布在仓库的 Releases 页面，并自动附上 `.ipk`, `.apk` 及自动化安装脚本 `install_openwrt_package.sh`。