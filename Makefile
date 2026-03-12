# This Makefile has been replaced by justfile.
#
# Usage:
#   export KSS_CLUSTER=kss
#   just help
#
# See README.md for full documentation.

.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "  This Makefile has been retired. Use 'just' instead:"
	@echo ""
	@echo "    export KSS_CLUSTER=kss"
	@echo "    just help"
	@echo ""
	@echo "  See README.md for documentation."
	@echo ""

%:
	@echo "Target '$@' has been moved to justfile. Run 'just help' for available commands."
