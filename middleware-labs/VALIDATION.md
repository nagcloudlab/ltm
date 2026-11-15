# Checks on the supplied materials

- Guide links and shell command syntax are checked.
- Project files match the included SHA256SUMS manifest.
- The Tomcat distribution matches Apache’s official checksum.
- Prepared WAR endpoints were exercised on Tomcat 10.1.61 and Java 21: healthy/JSON 200, deliberate 500, missing/broken context 404, invalid delay 400 and a 15-second slow response.
- Kong OSS 3.9.1 packages and the signing-key endpoint are available in the official Ubuntu 24.04 repository for AMD64 and ARM64. The downloaded AMD64 package matches its repository checksum; its executable path and CLI options were inspected.

**Runtime limitation:** the complete native Ubuntu/systemd stack and Kong scenarios have not been verified end-to-end. Use each guide’s process, port, response and log checks before proceeding to the next exercise.
