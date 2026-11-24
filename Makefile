PKGS = Core Capture Transcribe Enhance Output Theme EditorKit Pipeline
-include mk/agent.mk
.PHONY: gen build test verify selftest setup-signing install
gen:
	xcodegen generate
build: gen
	xcodebuild -project AppleRecorder.xcodeproj -scheme AppleRecorder -configuration Debug -derivedDataPath build build
test:
	@for p in $(PKGS); do echo "== $$p"; (cd Packages/$$p && swift test) || exit 1; done
verify:
	./scripts/verify.sh
selftest: build
	./scripts/verify.sh --selftests
setup-signing:
	./scripts/setup-local-signing.sh
install: gen
	xcodebuild -project AppleRecorder.xcodeproj -scheme AppleRecorder -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
	./scripts/sign-local.sh build/Build/Products/Release/AppleRecorder.app
	rm -rf /Applications/AppleRecorder.app
	cp -R build/Build/Products/Release/AppleRecorder.app /Applications/
