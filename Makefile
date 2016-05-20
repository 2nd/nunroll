t:
	@mkdir -p bin
	@nim c --out:./bin/tests --nimcache:./bin/nimcache nunroll_test.nim
	@./bin/tests
