.PHONY: build package release clean

build:
	./scripts/build-xcsoar.sh

package:
	./scripts/package-xcsoar.sh

release: build package

clean:
	rm -rf dist
