#!/usr/local/bin/managed_python3

import argparse
import string
import os
import subprocess
import tempfile
import shutil
import stat
import plistlib

# 
# quickpkg
# 


quickpkg_version = '1.0beta'
supported_extensions = ['dmg', 'app', 'zip', 'xip']


# modeled after munkiimport but to build a pkg


def logger(log, v=0):
    if args.verbosity >= v:
        print(log)


def cmdexec(command, stdin=''):
    """Execute a command."""
    # if 'command' is a string, split the string into components
    if isinstance(command, str):
        command = command.split()

    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
    (stdout, stderr) = proc.communicate(stdin)

    logger("cmdexec: %s, result: %s, error: %s" % (command, stdout, stderr), 3)

    # strip trailing whitespace, which would mess with string comparisons
    return {"return_code": proc.returncode, "stderr": stderr.rstrip(), "stdout": stdout.rstrip()}


# from munkicommons.py
def getFirstPlist(textString):
    """Gets the next plist from a text string that may contain one or
    more text-style plists.
    Returns a tuple - the first plist (if any) and the remaining
    string after the plist"""
    plist_header = b"<?xml version"
    plist_footer = b"</plist>"
    plist_start_index = textString.find(plist_header)
    if plist_start_index == -1:
        # not found
        return ("", textString)
    plist_end_index = textString.find(
        plist_footer, plist_start_index + len(plist_header))
    if plist_end_index == -1:
        # not found
        return ("", textString)
    # adjust end value
    plist_end_index = plist_end_index + len(plist_footer)
    return (textString[plist_start_index:plist_end_index],
            textString[plist_end_index:])


def dmg_has_sla(dmgpath):
    has_sla = False
    imageinfo_cmd = ['/usr/bin/hdiutil', 'imageinfo', dmgpath, '-plist']
    result = cmdexec(imageinfo_cmd)
    if result["return_code"] != 0:
        print("error getting imageinfo! %s, %s" % (result["return_code"], result["stderr"]))
        return False
    result_plist = result["stdout"]
    imageinfo_dict = plistlib.loads(result_plist)
    properties = imageinfo_dict.get('Properties')
    if properties is not None:
        has_sla = properties.get('Software License Agreement', False)
    return has_sla


def attachdmg(dmgpath):
    global dmg_was_mounted
    info_cmd = ["hdiutil", "info", "-plist"]
    info_result = cmdexec(info_cmd)
    if info_result["return_code"] == 0:
        # parse the plist output
        (theplist, alltext) = getFirstPlist(info_result["stdout"])
        info_dict = plistlib.loads(theplist)
        volpaths = []
        if "images" in list(info_dict.keys()):
            for y in info_dict["images"]:
                if "image-path" in list(y.keys()):
                    if y["image-path"] == dmgpath and os.path.samefile(y["image-path"], dmgpath):
                        for x in y.get("system-entities"):
                            if "mount-point" in list(x.keys()):
                                volpaths.append(x["mount-point"])
                                dmg_was_mounted = True
                        return volpaths
    else:
        print("error getting hdiutil info")
        print("(%d, %s)" % (info_result["returncode"], info_result["stderr"]))
        cleanup_and_exit(1)

    attachcmd = ["/usr/bin/hdiutil",
                 "attach",
                 dmgpath,
                 "-mountrandom",
                 "/private/tmp",
                 "-plist",
                 "-nobrowse"]
    if dmg_has_sla(dmgpath):
        stdin = "Y\n"
        print("NOTE: Disk image %s has a license agreement!" % dmgpath)
    else:
        stdin = ''
    result = cmdexec(attachcmd, stdin)
    if result["return_code"] == 0:
        # parse the plist output
        (theplist, alltext) = getFirstPlist(result["stdout"])
        resultdict = plistlib.loads(theplist)
        volpaths = []
        for x in resultdict["system-entities"]:
            if x["potentially-mountable"]:
                if x["volume-kind"] == 'hfs':
                    volpaths.append(x["mount-point"])
        # return the paths to mounted volume
        return volpaths
    else:
        print("error mounting disk image")
        print("(%d, %s)" % (result["returncode"], result["stderr"]))
        cleanup_and_exit(1)


def detachpaths(volpaths):
    for x in volpaths:
        if os.path.exists(x):
            if os.path.ismount(x):
                detachcmd = ["/usr/bin/hdiutil", "detach", x]
                cmdexec(detachcmd)


def finditemswithextension(dirpath, item_extension):
    foundapps = []
    if os.path.exists(dirpath):
        for x in os.listdir(dirpath):
            (item_basename, item_extension) = os.path.splitext(x)
            item_extension = item_extension.lstrip('.')
            if item_extension == 'app':
                foundapps.append(os.path.join(dirpath, x))
    else:
        print("path %s does not exist" % dirpath)
        cleanup_and_exit(1)
    return foundapps


def appNameAndVersion(app_path):
    info_path = os.path.join(app_path, "Contents/Info.plist")
    if not os.path.exists(info_path):
        print("Application at path %s does not have Info.plist" % app_path)
        # TODO: cleanup volumes here
        cleanup_and_exit(1)
    with open(info_path, 'rb') as info_file:
        info_plist = plistlib.load(info_file)
    app_name = info_plist.get("CFBundleName")
    if app_name is None:
        app_name = info_plist.get("CFBundleDisplayName")
        if app_name is None:
            (app_name, app_ext) = os.path.splitext(os.path.basename(app_path))
    app_identifier = info_plist.get("CFBundleIdentifier")
    app_version = info_plist.get("CFBundleShortVersionString")
    if app_version is None or app_version == "":
        app_version = info_plist.get("CFBundleVersion")
    return (app_name, app_identifier, app_version)


def cleanup_and_exit(returncode):
    global dmgvolumepaths
    global dmg_was_mounted
    global tmp_path
    
    if args.clean:
        if not dmg_was_mounted:
            detachpaths(dmgvolumepaths)
        if tmp_path is not None:
            shutil.rmtree(tmp_path)
    exit(returncode)


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="""Attempts to build a pkg from the input.
                                                 Installer item can be a dmg, zip, or app.""",
                                     epilog="""Example: quickpkg /path/to/installer_item""")

    # takes a path as input
    parser.add_argument('item_path', help="path to the installer item")

    scripts_group = parser.add_argument_group('Installation Scripts',
        '''These options will set the installation scripts. You pass an entire folder of scripts,
            just like the option of `pkgbuild` or you can give a file for the preinstall or postinstall
            scripts respectively. If you give both the --scripts and either one or both of --preinstall
            and --postinstall, quickpkg will attempt to merge, but throw an error if it cannot.''')
    scripts_group.add_argument('--scripts', help="path to a folder with scripts")
    scripts_group.add_argument('--preinstall', '--pre', help="path to the preinstall script")
    scripts_group.add_argument('--postinstall', '--post', help="path to the postinstall script")

    parser.add_argument('--install-location', dest='install_location', help='sets the install-location of the resulting pkg, default is "/Applications"')
    parser.set_defaults(install_location='/Applications')
    parser.add_argument('--ownership', choices=['recommended', 'preserve', 'preserve-other'],
                        help="will be passed through to pkgbuild")
    parser.add_argument('--output', '--out', '-o',
        help='''path where the package file will be created. If you give the full filename
                then you can use '{name}', '{version}' and '{identifier}' as placeholders.
                If this is a directory, then the
                package will be created with the default filename {name}-{version}.pkg''')

    parser.add_argument('--clean', dest='clean', action='store_true', help="clean up temp files (DEFAULT)")
    parser.add_argument('--no-clean', dest='clean', action='store_false', help=" do NOT clean up temp files")
    parser.set_defaults(clean=True)

    parser.add_argument('--relocatable', dest='relocatable', action='store_true',
                        help="sets BundleIsRelocatable in the PackageInfo to true")
    parser.add_argument('--no-relocatable', dest='relocatable', action='store_false',
                        help="sets BundleIsRelocatable in the PackageInfo (DEFAULT is false)")
    parser.set_defaults(relocatable=False)
    
    parser.add_argument('--sign',
                        help='Adds a digital signature to the resulting package.')
    parser.add_argument('--keychain',
                        help='Specify a specific keychain to search for the signing identity.')
    parser.add_argument('--cert',
                        help='Specify an intermediate certificate to be embedded in the package.')

    parser.add_argument("-v", "--verbosity", action="count", default=0, help="controls amount of logging output (max -vvv)")
    parser.add_argument('--version', help='prints the version', action='version', version=quickpkg_version)

    args = parser.parse_args()

    # remove trailing '/' from path
    item_path = args.item_path.rstrip('/')

    if item_path.startswith('~'):
        item_path = os.path.expanduser(item_path)
    item_path = os.path.abspath(item_path)

    # get file extension
    (item_basename, item_extension) = os.path.splitext(item_path)
    item_extension = item_extension.lstrip('.')

    # is extension supported
    if item_extension not in supported_extensions:
        print(".%s is not a supported extension!" % item_extension)
        exit(1)

    foundapps = []
    copy_app = False

    # if item is an app, just pass it on
    if item_extension == 'app':
        if not os.path.exists(item_path):
            print("This does not seem to be an Application!")
            exit(1)
        foundapps.append(item_path)
        copy_app = True

    dmgvolumepaths = []
    tmp_path = None
    dmg_was_mounted = False
    tmp_scripts_path = None
    tmp_path = tempfile.mkdtemp()
    payload_path = os.path.join(tmp_path, "payload")
    os.makedirs(payload_path)

    # if item is a dmg, mount it and find useful contents
    if item_extension == 'dmg':
        dmgvolumepaths = attachdmg(item_path)
        copy_app=True
        for x in dmgvolumepaths:
            moreapps = finditemswithextension(x, 'app')
            foundapps.extend(moreapps)
        if len(foundapps) == 0:
            print("Could not find an application!")
            cleanup_and_exit(1)
        elif len(foundapps) > 1:
            print("Found too many Applications! Can't decide!")
            print(foundapps)
            cleanup_and_exit(1)
        
    # if item is zip, unzip to tmp location and find useful contents
    if item_extension == 'zip':
        unarchive_path = os.path.join(tmp_path, "unarchive")
        unzip_cmd = ["/usr/bin/unzip", "-d", unarchive_path, item_path]
        result = cmdexec(unzip_cmd)
        if result["return_code"] != 0:
            print("An error occured while unzipping:")
            print("%d, %s" % (result["return_code"], result["stderr"]))
            cleanup_and_exit(1)
        foundapps = finditemswithextension(unarchive_path, 'app')
        if len(foundapps) == 0:
            print("Could not find an application!")
            cleanup_and_exit(1)
        elif len(foundapps) > 1:
            print("Found too many Applications! Can't decide!")
            print(foundapps)
            cleanup_and_exit(1)

    # if item is xip, extract to tmp location and find useful contents
    if item_extension == 'xip':
        cwd = os.getcwd()
        unarchive_path = os.path.join(tmp_path, "unarchive")
        os.makedirs(unarchive_path)
        os.chdir(unarchive_path)
        xip_cmd = ["/usr/bin/xip", "--expand", item_path]
        result = cmdexec(xip_cmd)
        os.chdir(cwd)
        if result["return_code"] != 0:
            print("An error occured while expanding xip archive:")
            print("%d, %s" % (result["return_code"], result["stderr"]))
            cleanup_and_exit(1)
        foundapps = finditemswithextension(unarchive_path, 'app')
        if len(foundapps) == 0:
            print("Could not find an application!")
            cleanup_and_exit(1)
        elif len(foundapps) > 1:
            print("Found too many Applications! Can't decide!")
            print(foundapps)
            cleanup_and_exit(1)

    logger("Found application: %s" % foundapps[0], 1)

    # copy or move found app to payload folder
    app_name = os.path.basename(foundapps[0])
    app_path = os.path.join(payload_path, app_name)
    if copy_app:
        shutil.copytree(foundapps[0], app_path, symlinks=True)
    else:
        shutil.move(foundapps[0], app_path)
    

    # extract version and other metadata
    (app_name, app_identifier, app_version) = appNameAndVersion(app_path)

    logger("Name: %s, ID: %s, Version: %s" % (app_name, app_identifier, app_version), 1)

    # create the component plist
    component_plist = os.path.join(tmp_path, app_identifier) + ".plist"
    analyzecmd = ["/usr/bin/pkgbuild",
                  "--analyze",
                  "--root", payload_path,
                  "--identifier", app_identifier,
                  "--version", app_version,
                  "--install-location", args.install_location,
                  component_plist]
    result = cmdexec(analyzecmd)

    logger(result["stdout"], 1)
    if result["return_code"] != 0:
        print("Error Code: %d " % result["return_code"])
        print(result["stderr"])
        cleanup_and_exit(1)
    
    if not args.relocatable:
        # read and change component plist
        with open(component_plist, 'rb') as component_file:
            components = plistlib.load(component_file)
        # component plist is an array of components
        for bundle in components:
            if "BundleIsRelocatable" in list(bundle.keys()):
                bundle["BundleIsRelocatable"] = False
        with open(component_plist, 'wb') as component_file:
            plistlib.dump(components, component_file, fmt=plistlib.FMT_XML)
    
    pkg_name = "{name}-{version}.pkg"
    if args.output:
        if os.path.isdir(args.output):
            pkg_path = os.path.join(args.output, pkg_name)
        else:
            pkg_path = args.output
    else:
        pkg_path = pkg_name
    nospace_app_name = app_name.replace(' ', '')  # remove spaces
    pkg_path = pkg_path.format(name=nospace_app_name, version=app_version, identifier=app_identifier)

    if not pkg_path.endswith('pkg'):
        pkg_path += '.pkg'

    # run pkgutil to build result
    pkgcmd = ["/usr/bin/pkgbuild",
              "--root", payload_path,
              "--component-plist", component_plist,
              "--identifier", app_identifier,
              "--version", app_version,
              "--install-location", args.install_location,
              pkg_path]

    if args.scripts and not os.path.exists(args.scripts):
        print("scripts folder %s does not exist!" % args.scripts)
        cleanup_and_exit(1)

    if args.postinstall or args.preinstall:
        tmp_scripts_path = os.path.join(tmp_path, "scripts")
        os.makedirs(tmp_scripts_path)
        
        if args.scripts:
            logger("copying %s to tmp scripts folder %s" % (args.scripts, tmp_scripts_path), 1)
            shutil.rmtree(tmp_scripts_path)
            shutil.copytree(args.scripts, tmp_scripts_path)
        if args.postinstall:
            if not os.path.exists(args.postinstall):
                print("postinstall file %s does not exist!" % args.postinstall)
                cleanup_and_exit(1)
            postinstall_path = os.path.join(tmp_scripts_path, "postinstall")
            if os.path.exists(postinstall_path):
                print("postinstall script already exists in %s" % args.scripts)
                cleanup_and_exit(1)
            logger("copying %s to %s" % (args.postinstall, postinstall_path), 1)
            shutil.copy2(args.postinstall, postinstall_path)
            os.chmod(postinstall_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                       stat.S_IRGRP | stat.S_IXGRP |
                                       stat.S_IROTH | stat.S_IXOTH)
        if args.preinstall:
            if not os.path.exists(args.preinstall):
                print("preinstall file %s does not exist!" % args.preinstall)
                cleanup_and_exit(1)
            preinstall_path = os.path.join(tmp_scripts_path, "preinstall")
            if os.path.exists(preinstall_path):
                print("preinstall script already exists in %s" % args.scripts)
                cleanup_and_exit(1)
            logger("copying %s to %s" % (args.preinstall, preinstall_path), 1)
            shutil.copy2(args.preinstall, preinstall_path)
            os.chmod(preinstall_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                      stat.S_IRGRP | stat.S_IXGRP |
                                      stat.S_IROTH | stat.S_IXOTH)

    if tmp_scripts_path:
        logger("scripts path: %s" % tmp_scripts_path, 1)
        pkgcmd.extend(["--scripts", tmp_scripts_path])
    elif args.scripts:
        logger("scripts path: %s" % args.scripts, 1)
        pkgcmd.extend(["--scripts", args.scripts])

    if args.ownership:
        pkgcmd.extend(["--ownership", args.ownership])

    if args.sign:
        pkgcmd.extend(["--sign", args.sign])
    if args.keychain:
        pkgcmd.extend(["--keychain", args.keychain])
    if args.cert:
        pkgcmd.extend(["--cert", args.cert])
    result = cmdexec(pkgcmd)

    logger(result["stdout"], 1)
    if result["return_code"] != 0:
        print("Error Code: %d " % result["return_code"])
        print(result["stderr"])
    else:
        print(pkg_path)

    cleanup_and_exit(0)
