# Included by the Makefile (-include mk/agent.mk)
.PHONY: hooks tasks protect step sdk-dump
hooks:
	git config core.hooksPath scripts/hooks
	@echo "pre-commit hook installed"
tasks:
	python3 scripts/split-guide.py
protect:
	./scripts/protect-tests.sh
step:
	@test -n "$(STEP)" || (echo "usage: make step STEP=P1 AGENT_CMD='claude -p'"; exit 2)
	./scripts/run-step.sh $(STEP)
sdk-dump:
	./scripts/dump-sdk-interfaces.sh
