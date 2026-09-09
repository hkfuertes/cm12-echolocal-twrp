.PHONY: prepare package verify test clean

prepare:
	./scripts/fetch-inputs.sh

package: prepare
	./scripts/build-zip.sh

verify: package
	./scripts/verify-zip.sh

test: package
	./scripts/verify-zip.sh
	./tests/test-repair.sh
	./tests/test-wifi.sh
	./tests/test-zip.sh

clean:
	rm -rf work out
