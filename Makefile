SHELL := /bin/sh

# Overridable so tests/test_deploy_exit_codes.sh can stub each stage.
SOPS_CMD           ?= sops --decrypt ansible/vars/secrets.enc.yml
SECRETS_FILE       := ansible/vars/secrets.yml
# -e @$(SECRETS_FILE) wires stage 1's decrypted output into stage 2 — without
# it, SOPS_CMD's output is decrypted and discarded, never reaching ansible.
ANSIBLE_CMD        ?= ansible-playbook -i ansible/inventory/ ansible/playbook.yml -e @$(SECRETS_FILE)
CONNECTIVITY_CHECK ?= echo "connectivity check stub"

.PHONY: deploy test test-deploy _check-prereqs

# Guards AC-9 (fresh-workstation reproducibility): fail loudly before any
# side effect rather than partway through a stage.
_check-prereqs:
	@for bin in ansible sops age; do \
		command -v $$bin >/dev/null 2>&1 || { echo "ERROR: $$bin not found — install it before running make deploy" >&2; exit 1; }; \
	done

deploy: _check-prereqs
	@trap 'rm -f $(SECRETS_FILE)' EXIT; \
	$(SOPS_CMD) > $(SECRETS_FILE) || { echo "ERROR: SOPS decrypt failed — check AGE_SECRET_KEY or ~/.config/sops/age/keys.txt" >&2; exit 1; }; \
	$(ANSIBLE_CMD) || { echo "ERROR: ansible-playbook failed — see output above" >&2; exit 1; }; \
	$(CONNECTIVITY_CHECK) || { echo "ERROR: Connectivity check failed — proxy stack may not be reachable" >&2; exit 1; }; \
	exit 0

test-deploy:
	sh tests/test_deploy_exit_codes.sh

test: test-deploy
