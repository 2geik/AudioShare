APP := build/AudioShare.app

.PHONY: app run install icons clean

app:
	./Scripts/build-app.sh

run: app
	-pkill -x AudioShare
	open $(APP)

install: app
	-pkill -x AudioShare
	rm -rf /Applications/AudioShare.app
	cp -R $(APP) /Applications/
	open /Applications/AudioShare.app

icons:
	./Scripts/make-icons.sh

clean:
	rm -rf .build build
