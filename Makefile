SHELL := /bin/sh

# Overridable so tests/test_deploy_exit_codes.sh can stub each stage.
SOPS_CMD           ?= sops --decrypt ansible/vars/secrets.enc.yml
SECRETS_FILE       := ansible/vars/secrets.yml
# -e @$(SECRETS_FILE) wires stage 1's decrypted output into stage 2 — without
# it, SOPS_CMD's output is decrypted and discarded, never reaching ansible.
ANSIBLE_CMD        ?= ansible-playbook -i ansible/inventory/ ansible/playbook.yml -e @$(SECRETS_FILE)
CONNECTIVITY_CHECK ?= echo "connectivity check stub"
ROLES              ?= prerequisites amneziawg xray hysteria2 firewall
ANSIBLE_ROLES_DIR  ?= ansible/roles

.PHONY: deploy setup client-config test test-deploy test-molecule _check-prereqs

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

setup:
	@[ -n "$(IP)" ]       || { echo "Usage: make setup IP=<address> PASSWORD=<root-password>" >&2; exit 1; }
	@[ -n "$(PASSWORD)" ] || { echo "Usage: make setup IP=<address> PASSWORD=<root-password>" >&2; exit 1; }
	@scripts/setup-server.sh "$(IP)" "$(PASSWORD)"

test-deploy:
	sh tests/test_deploy_exit_codes.sh

# Iterates $(ROLES) in order; halts on the first failing role and names it.
# Molecule itself distinguishes skipped from failed — this loop must not
# post-process that, just propagate molecule test's exit code verbatim.
# --all: firewall has a second scenario (empty-whitelist) covering the
# lockout-guard edge case; plain `molecule test` only runs "default" and
# would silently skip it. --all is a no-op for every other role here.
test-molecule:
	@for role in $(ROLES); do \
		case "$$role" in \
			prerequisites) acs="AC-3, AC-9" ;; \
			amneziawg) acs="AC-1 (partial — kernel module skipped in Docker), AC-3" ;; \
			xray) acs="AC-3, AC-4, AC-5" ;; \
			hysteria2) acs="AC-3, AC-4, AC-5" ;; \
			firewall) acs="AC-3, AC-6" ;; \
			*) acs="" ;; \
		esac; \
		echo "=== [$$role] molecule test — covers: $$acs ==="; \
		( cd $(ANSIBLE_ROLES_DIR)/$$role && molecule test --all ); \
		if [ $$? -ne 0 ]; then \
			echo "ERROR: molecule test failed for role $$role" >&2; \
			exit 1; \
		fi; \
	done

test: test-deploy test-molecule
