//go:build linux

package tun

import (
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/sagernet/nftables"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/shell"
)

func (r *autoRedirect) configureOpenWRTFirewall4(nft *nftables.Conn, cleanup bool) error {
	_, err := nft.ListTableOfFamily("fw4", nftables.TableFamilyINet)
	if err != nil {
		return nil
	}
	fw4Path, err := exec.LookPath("fw4")
	if err != nil {
		return nil
	}
	rulePath := "/etc/nftables.d/0-" + r.tableName + "-auto-redirect.nft"
	if !cleanup {
		redirectPort := strconv.FormatUint(uint64(r.redirectPort()), 10)
		redirectRule := `tcp dport ` + redirectPort + ` counter accept comment "!` + r.tableName + `: Accept auto-redirect port"`
		if len(r.tunOptions.IncludeInterface) > 0 {
			if len(r.tunOptions.IncludeInterface) == 1 {
				redirectRule = `iifname "` + r.tunOptions.IncludeInterface[0] + `" ` + redirectRule
			} else {
				redirectRule = `iifname { ` + quoteNFTInterfaceList(r.tunOptions.IncludeInterface) + ` } ` + redirectRule
			}
		} else if len(r.tunOptions.ExcludeInterface) > 0 {
			if len(r.tunOptions.ExcludeInterface) == 1 {
				redirectRule = `iifname != "` + r.tunOptions.ExcludeInterface[0] + `" ` + redirectRule
			} else {
				redirectRule = `iifname != { ` + quoteNFTInterfaceList(r.tunOptions.ExcludeInterface) + ` } ` + redirectRule
			}
		}
		err = os.WriteFile(rulePath, []byte(`chain input {
	type filter hook input priority filter; policy accept;
	iifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
	oifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
	`+redirectRule+`
}
chain forward {
	type filter hook forward priority filter; policy accept;
	iifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
	oifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
}
`), 0o644)
		if err != nil {
			return E.Cause(err, "write fw4 rules")
		}
	} else if _, err = os.Stat(rulePath); os.IsNotExist(err) {
		return nil
	} else {
		err = os.Remove(rulePath)
		if err != nil {
			return E.Cause(err, "clean fw4 rules")
		}
	}
	output, err := shell.Exec(fw4Path, "reload").Read()
	if err != nil {
		return E.Extend(E.Cause(err, "reload fw4 rules"), output)
	}
	return nil
}

func quoteNFTInterfaceList(names []string) string {
	return `"` + strings.Join(names, `", "`) + `"`
}
