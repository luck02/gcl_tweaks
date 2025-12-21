# Avorion QOL Mod - Development Makefile
#
# make test          - Run tests
# make pr            - Create PR for review  
# make release       - Bump patch version and deploy
# make release-minor - Bump minor version and deploy
# make release-major - Bump major version and deploy

.PHONY: test pr release release-minor release-major help

# Default target
help:
	@echo "Available targets:"
	@echo "  make test          - Run the test suite"
	@echo "  make pr            - Create a PR for current branch"
	@echo "  make release       - Bump patch version and deploy (1.2.3 -> 1.2.4)"
	@echo "  make release-minor - Bump minor version and deploy (1.2.3 -> 1.3.0)"
	@echo "  make release-major - Bump major version and deploy (1.2.3 -> 2.0.0)"

# Run tests
test:
	@echo "🧪 Running tests..."
	lua run_tests.lua --verbose

# Create PR for review (from feature branch)
pr:
	@CURRENT_BRANCH=$$(git branch --show-current); \
	if [ "$$CURRENT_BRANCH" = "main" ]; then \
		echo "❌ Cannot push from main. Create a feature branch first:"; \
		echo "   git checkout -b feature/your-feature"; \
		exit 1; \
	fi; \
	echo "📤 Pushing branch $$CURRENT_BRANCH..."; \
	git push -u origin "$$CURRENT_BRANCH"; \
	echo "📝 Creating PR..."; \
	gh pr create --fill || echo "PR may already exist"

# Bump patch version (1.2.3 -> 1.2.4) and deploy
release: _bump-patch _deploy

# Bump minor version (1.2.3 -> 1.3.0) and deploy
release-minor: _bump-minor _deploy

# Bump major version (1.2.3 -> 2.0.0) and deploy
release-major: _bump-major _deploy

# Internal: bump patch version
_bump-patch:
	@CURRENT=$$(grep -o 'version = "[^"]*"' modinfo.lua | cut -d'"' -f2); \
	NEW=$$(echo $$CURRENT | awk -F. '{print $$1"."$$2"."$$3+1}'); \
	echo "📦 Bumping version: $$CURRENT -> $$NEW"; \
	sed -i 's/version = "[^"]*"/version = "'$$NEW'"/' modinfo.lua

# Internal: bump minor version  
_bump-minor:
	@CURRENT=$$(grep -o 'version = "[^"]*"' modinfo.lua | cut -d'"' -f2); \
	NEW=$$(echo $$CURRENT | awk -F. '{print $$1"."$$2+1".0"}'); \
	echo "📦 Bumping version: $$CURRENT -> $$NEW"; \
	sed -i 's/version = "[^"]*"/version = "'$$NEW'"/' modinfo.lua

# Internal: bump major version
_bump-major:
	@CURRENT=$$(grep -o 'version = "[^"]*"' modinfo.lua | cut -d'"' -f2); \
	NEW=$$(echo $$CURRENT | awk -F. '{print $$1+1".0.0"}'); \
	echo "📦 Bumping version: $$CURRENT -> $$NEW"; \
	sed -i 's/version = "[^"]*"/version = "'$$NEW'"/' modinfo.lua

# Internal: commit and push to main
_deploy:
	@echo "🧪 Running tests before release..."
	@lua run_tests.lua --verbose || { echo "❌ Tests failed. Release aborted."; exit 1; }
	@NEW=$$(grep -o 'version = "[^"]*"' modinfo.lua | cut -d'"' -f2); \
	echo "✅ Tests passed. Committing version $$NEW..."; \
	git add modinfo.lua; \
	git commit -m "chore: release v$$NEW"; \
	echo "🚀 Pushing to main..."; \
	git push origin main; \
	echo ""; \
	echo "🎉 Release v$$NEW triggered!"; \
	echo "   GitHub Actions will create the release and deploy to Steam Workshop."
