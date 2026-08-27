LOCALE_DISABLE_POOTLE_DOWNLOAD=1

TEST_TARGETS += route_hooks

.PHONY: route_hooks
route_hooks:
	./tests/route-hooks.sh
