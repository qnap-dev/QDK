import sys
import os
import logging
import subprocess
import shutil
import codesigning_common
from codesigning_common import data_to_string

def check_qpkg_conf(kwargs):
    # Check if qpkg.cfg exists, and read paramaters from it

    if "cfgpath" in kwargs and kwargs["cfgpath"] != "":
        qpkg_conf = os.path.join(kwargs["cwd"],kwargs["cfgpath"])
    else:
        qpkg_conf = os.path.join(kwargs["cwd"],"qpkg.cfg")
    if not os.path.isfile(qpkg_conf):
        logging.error("Cannot find qpkg.cfg")
        sys.exit(1)
    commands = ["source %s" % qpkg_conf, "echo $QPKG_NAME"]
    sp = subprocess.Popen("bash",stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    for cmd in commands:
        cmdline = cmd + "\n"
        sp.stdin.write(cmdline.encode())
    sp.stdin.close()
    kwargs["qpkgname"] = data_to_string(sp.stdout.read()).strip()

    commands = ["source %s" % qpkg_conf, "echo $QPKG_VER"]
    sp = subprocess.Popen("bash",stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    for cmd in commands:
        cmdline = cmd + "\n"
        sp.stdin.write(cmdline.encode())
    sp.stdin.close()
    kwargs["version"] = data_to_string(sp.stdout.read()).strip()

    if kwargs["qpkgname"] == "":
        logging.error("Cannot find QPKG_NAME in qpkg.cfg")
        sys.exit(1)
    if kwargs["version"] == "":
        logging.error("Cannot find QPKG_VER in qpkg.cfg")
        sys.exit(1)

def sign_and_save_cms(kwargs):
    # Send to server
    kwargs["file"] = kwargs["in"]
    response = codesigning_common.sign_cms(kwargs)
    if response["error"] != 0:
        logging.error("Error message from server when signing cms: %s" % response["msg"])
        sys.exit(1)
    signature = response["signature"]

    # Save to file
    signature_file_name = kwargs["out"]
    signature_file = open(signature_file_name, "w")
    signature_file.write(signature)
    signature_file.close()

def print_usage():
    usage_string = """
    Usage:
      Sign a single file using openssl cms:
        python codesigning_qpkg_cms.py server=x.x.x.x:port cwd=working_directory cert=certificate.pem
          in=input_file out=output_file key_ver=key_version

      working directory: the folder where developers run build.sh
      cert: certificate of code signing server (optional)
      key_type: indicate if it is qpkg or qfix (optional, default is qpkg)
      cfgpath: relative path of qpkg.cfg (optional, default is qpkg.cfg)
      key_ver: version of key used for signing (optional)

      Sign without cfg:
        python codesigning_qpkg_cms.py server=x.x.x.x:port qpkgname=qpkg_name version=qpkg_version cert=certificate.pem
          in=input_file out=output_file key_ver=key_version
    """
    print (usage_string)

if __name__ == "__main__":
    # Config logging
    codesigning_common.config_logging()

    try:
        kwargs = dict(arg.split('=') for arg in sys.argv[1:])
    except:
        print_usage()
        sys.exit(1)
    if "server" not in kwargs or "in" not in kwargs or "out" not in kwargs or \
            (len(kwargs) != 4 and len(kwargs) != 5 and len(kwargs) != 6 and len(kwargs) != 7 and len(kwargs) != 8):
        print_usage()
        sys.exit(1)
    codesigning_common.check_args(kwargs)
    kwargs["token"] = codesigning_common.get_token()
    kwargs["key_type"] = "qpkg"
    if "cwd" in kwargs:
        codesigning_common.check_cwd(kwargs)
        check_qpkg_conf(kwargs)
    else:
        if kwargs["qpkgname"] == "":
            logging.error("qpkgname not provided")
            sys.exit(1)
        if kwargs["version"] == "":
            logging.error("version not provided")
            sys.exit(1)
    sign_and_save_cms(kwargs)
