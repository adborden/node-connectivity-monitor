deploy:
	cp -R systemd/* ~/.local/share/systemd/user/
	cp -R scripts/* ~/.local/bin/
	systemctl --user daemon-reload
