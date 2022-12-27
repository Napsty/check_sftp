# check_sftp
This is a monitoring plugin written in Bash to check SFTP servers. The plugin supports both key and password authentication. Both open and encrypted (by passphrase) private keys are supported. The plugin will attempt to establish a connection to a specified SFTP server `-H`. After a successful connection, the plugin will upload and then download a temporary file into a specified remote directory `-d`.

This is the public repository for development.

Please visit the link below for the latest release and documentation:

https://www.claudiokuenzler.com/monitoring-plugins/check_sftp.php
