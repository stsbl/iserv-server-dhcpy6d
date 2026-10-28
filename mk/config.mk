LOCALE_DISABLE_POOTLE_DOWNLOAD=1

TEST_TARGETS += route_hooks

.PHONY: route_hooks
route_hooks:
	./tests/route-hooks.sh

TEST_TARGETS += ipv6_config_tests

.PHONY: ipv6_config_tests
ipv6_config_tests:
	prove -r tests
