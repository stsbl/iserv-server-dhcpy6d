# Authenticated Reconfigure test setup

Use a test router and a downstream IServ/dhcpcd client, connected on an isolated
LAN. The router needs an upstream DHCPv6-PD connection and an existing working
STSBL DHCPv6 address/prefix-delegation configuration. Keep the server DUID and
`/var/lib/dhcpy6d/reconfigure.sqlite` across restarts. Never copy this private
key database to another router.

Install the built `dhcpy6d_1.7.0-1+stsblnmu5_all.deb` and
`stsbl-iserv-server-dhcpy6d_26.10.28.2_all.deb` on the router with `apt install`.
Install `stsbl-iserv-config-ipv6_26.10.28.1_all.deb` on router and client. Resolve
package dependencies from the normal IServ/STSBL repositories.

`DHCPv6Reconfigure` is enabled by default in the router's IServ configuration.
If it was explicitly disabled, enable it in the configuration editor. Run `iservchk dhcpy6d` on the router and `iservchk dhcpcd` on the client.
Verify `/etc/dhcpy6d.conf` contains:

```
reconfigure_state_file = /var/lib/dhcpy6d/reconfigure.sqlite
```

Verify the client's `/etc/dhcpcd.conf` requests `dhcp6_reconfigure_accept` and
retains DNS/search/Rapid Commit options. Do not configure `noauthrequired`.
The client needs a fresh initial DHCP exchange after enabling acceptance; on the
test client only, stop dhcpcd with lease release and start it again. Observe an
initial Request/Reply (or Rapid Commit) exchange before testing. A Renew alone
does not enroll an old lease. Capture on the router LAN:

```
tcpdump -ni LAN_INTERFACE -s0 -w reconfigure.pcap 'udp port 546 or udp port 547'
```

Record the delegated client prefix and route. Restart `dhcpy6d` on the router.
Expect an authenticated Reconfigure followed promptly by the client's Renew and
the server Reply, before the normal T1 timer expires. Keys/counters must survive
the restart; the route must remain usable.

On this test router, interrupt and restore the upstream DSL link. Check that
recovery of the same prefix triggers client renewal and restores the downstream
route. If a different prefix is delegated, verify the new delegated route and
client addresses, including any repeated Reconfigure needed to withdraw and
reallocate the old PD. Check `journalctl -u dhcpy6d -u dhcpcd`, the capture, and
`ip -6 route`; test connectivity to a downstream host. Prefix recovery must reach
dhcpy6d through the existing prefix-control/restart integration.

For repeatable isolated tests without DSL or host interface changes, use the
supplied package-test bundle's `run-tests.sh`. It installs the NMU binary into a
Docker image and runs real clients in private network namespaces. JUnit, logs,
PCAPs and kernel routes are retained. The four unsupported relay scenarios are
reported as known failures; capability skips remain visible.

To disable, clear `DHCPv6Reconfigure` and rerun `iservchk dhcpy6d`. Keep the state
file for later re-enrollment; do not remove it as part of lease cleanup.
