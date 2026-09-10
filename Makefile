.PHONY: prepare fetch echod-arm64 echod-armv7 package package-arm64 package-armv7 verify verify-arm64 verify-armv7 test clean

prepare: echod-arm64 echod-armv7

fetch:
	./scripts/fetch-inputs.sh

echod-arm64: fetch
	GOARCH=arm64 GOARM=7 ./scripts/build-echod.sh

echod-armv7: fetch
	GOARCH=arm GOARM=7 ./scripts/build-echod.sh

package: package-arm64 package-armv7

package-arm64: echod-arm64
	GOARCH=arm64 GOARM=7 ./scripts/build-zip.sh

package-armv7: echod-armv7
	GOARCH=arm GOARM=7 ./scripts/build-zip.sh

verify: verify-arm64 verify-armv7

verify-arm64: package-arm64
	GOARCH=arm64 GOARM=7 ./scripts/verify-zip.sh

verify-armv7: package-armv7
	GOARCH=arm GOARM=7 ./scripts/verify-zip.sh

test: verify
	./tests/test-repair.sh
	./tests/test-wifi.sh
	GOARCH=arm64 GOARM=7 ./tests/test-zip.sh
	GOARCH=arm GOARM=7 ./tests/test-zip.sh

clean:
	rm -rf work out
