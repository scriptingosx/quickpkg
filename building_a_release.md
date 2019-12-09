# building ACORN
1. Update the project target version to a new version e.g. 1.3.0 -> 1.3.1
2. Update the build number on the target to the next highest integer value e.g. 25 -> 26
3. In Xcode, run Project->Archive
4. From the Xcode Organizer, export the archive with Developer ID and upload to Apple for notarization 
(this can take a few minutes or more)
5. After receiving approval from Apple notorization, export the app, which will create an ACORN.app
6. Create a .pkg file from the app using quickpkg [GitHub - scriptingosx/quickpkg: wrapper for pkgbuild to 
quickly build simple packages from an installed app, a dmg or zip archive.](https://github.com/scriptingosx/quickpkg)
7. Send the .pkg file to Ray Duran to publish on JAMF…this will make it available for update on OCIO Self Service
(the JAMF user facing app where you can install or update your Mac apps)
8. Create the corresponding release in Github for this version, adding any relevant release notes and drop the .pkg 
file there into the release page as well so that anyone in a hurry can just go there and download it to install manually.
