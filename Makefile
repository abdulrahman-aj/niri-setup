.PHONY: test

TEST_FILES := tests/test-setup.sh tests/test-system.sh tests/test-desktop.sh \
              tests/test-brew.sh tests/test-development.sh \
              tests/test-docker.sh tests/test-commands.sh tests/test-optional.sh

test:
	@ok=1; for f in $(TEST_FILES); do bash "$$f" || ok=0; done; [ "$$ok" -eq 1 ]
