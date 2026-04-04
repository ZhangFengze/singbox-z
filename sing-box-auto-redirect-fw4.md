# sing-box auto_redirect 的 fw4 动态端口放行

## 目标

不做固定端口，不改 `sing-box` 配置层。  
只在 `auto_redirect` 已经拿到真实动态 redirect 端口后，插入现有 OpenWrt `fw4` 兼容逻辑，自动放行这个端口。

## 现状

`sing-tun` 里已经有 OpenWrt 兼容入口：

- 文件：`SagerNet/sing-tun/redirect_nftables_rules_openwrt.go`
- 函数：`configureOpenWRTFirewall4(nft, cleanup bool)`

现有逻辑会：

1. 检查 `fw4` 表是否存在
2. 检查系统里是否有 `fw4` 命令
3. 写入 `/etc/nftables.d/0-<table>-auto-redirect.nft`
4. 执行 `fw4 reload`

目前这个 `.nft` 文件只会放行 `tun` 接口方向的流量，不会额外放行内部动态 redirect 端口。

## 为什么这里可以插

`autoRedirect.Start()` 的时序已经满足要求：

1. 先启动内部 `redirectServer`
2. 这时动态端口已经分配完成
3. `r.redirectPort()` 可以返回真实端口
4. 然后执行 `setupNFTables()`
5. `setupNFTables()` 再调用 `configureOpenWRTFirewall4(nft, false)`

所以在 `configureOpenWRTFirewall4()` 里直接使用 `r.redirectPort()` 是成立的。

## 删除逻辑

不需要新增删除逻辑，直接复用现有 cleanup 流程。

现有关闭路径：

1. `autoRedirect.Close()`
2. `cleanupNFTables()`
3. `configureOpenWRTFirewall4(nft, true)`
4. 删除 `/etc/nftables.d/0-<table>-auto-redirect.nft`
5. 执行 `fw4 reload`

也就是说，只要把新规则写进同一个 `.nft` 文件里，关闭时就会随整个文件一起删除。

## 最小改法

只改一个文件：

- `SagerNet/sing-tun/redirect_nftables_rules_openwrt.go`

### 需要做的事

1. 增加 `strconv` import
2. 在 `!cleanup` 分支里取出当前动态端口
3. 在现有 `chain input` 中补一条 `tcp dport <redirectPort> accept`

### 建议代码形态

先取端口：

```go
redirectPort := strconv.FormatUint(uint64(r.redirectPort()), 10)
```

然后把当前写入的 `chain input` 扩成：

```go
chain input {
 type filter hook input priority filter; policy accept;
 iifname "` + r.tunOptions.Name + `" counter accept comment "!` + r.tableName + `: Accept traffic from tun"
 oifname "` + r.tunOptions.Name + `" counter accept comment "!` + r.tableName + `: Accept traffic from tun"
 tcp dport ` + redirectPort + ` counter accept comment "!` + r.tableName + `: Accept auto-redirect port"
}
```

## 约束

- 不改 `sing-box/protocol/tun/inbound.go`
- 不改 `sing-tun/redirect_linux.go`
- 不改 `redirectServer`
- 不改 `CustomRedirectPort`
- 不新增独立 cleanup 分支
- 不改成增量插 rule，继续沿用“重写整个规则文件”的方式

## 风险

最小版规则：

```nft
tcp dport <redirectPort> accept
```

这条规则没有接口限制，可能会放宽到其他入口接口。  
所以第一版建议先做 PoC，确认问题确实是缺这条放行规则。

如果 PoC 生效，再考虑第二版收窄范围，例如：

- 限制到指定 `iifname`
- 或排除 `wan`

## 验证

启动 `sing-box` 后检查：

1. `/etc/nftables.d/0-sing-box-auto-redirect.nft` 是否包含动态端口规则
2. `fw4 reload` 是否成功
3. `nft list ruleset` 是否能看到该规则
4. 原本失败的场景是否恢复

关闭 `sing-box` 后检查：

1. 规则文件是否被删除
2. `nft list ruleset` 中对应规则是否消失

## 和当前脚本方案的关系

你现在的 `Homelab/sing-box` 已经是用户态绕过方案：

- 启动后去 `nft list chain inet sing-box prerouting`
- 解析动态 redirect 端口
- 再手动往 `fw4` 插 `accept`

这份文档描述的是上游源码里的最小实现方式，本质上是在 `sing-tun` 内部把这件事内建掉，而不是继续依赖外部脚本。
