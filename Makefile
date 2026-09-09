help:
	@echo "Available targets:"
	@echo "  run        - Bootstrap the full environment (install tools, provision cluster)"
	@echo "  down       - Destroy the cluster and all resources"
	@echo "  push       - Bump patch version, tag, and push to trigger CI"
	@echo "  tools      - Install necessary tools only"
	@echo "  tofu       - Initialize OpenTofu"
	@echo "  apply      - Apply OpenTofu configuration"
	@echo "  fix-egress - Repair nested-Docker egress (Codespaces) and verify nodes"

run:
	@bash scripts/setup.sh

tools:
	@curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method standalone
	@curl -sS https://webi.sh/k9s | bash
	@ARCH=$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); \
	  OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.33.0/kind-$$OS-$$ARCH" && \
	  sudo install -m 0755 /tmp/kind /usr/local/bin/kind && rm -f /tmp/kind

fix-egress:
	@bash scripts/fix-egress.sh
	@bash scripts/fix-egress.sh verify abox

tofu:
	@cd bootstrap && tofu init

apply:
	@cd bootstrap && tofu apply -auto-approve

down:
	@cd bootstrap && tofu destroy -auto-approve

push:
	@git fetch origin --tags --force
	$(eval TAG=$(shell git tag --list 'v*' | sort -V | tail -1 | sed 's/^v//' || echo "0.0.0"))
	$(eval MAJOR=$(shell echo $(TAG) | cut -d. -f1))
	$(eval MINOR=$(shell echo $(TAG) | cut -d. -f2))
	$(eval PATCH=$(shell echo $(TAG) | cut -d. -f3))
	$(eval NEW_TAG=v$(MAJOR).$(MINOR).$(shell echo $$(($(PATCH)+1))))
	@git tag $(NEW_TAG)
	@git push origin main $(NEW_TAG)
	@echo "Tagged and pushed $(NEW_TAG)"
