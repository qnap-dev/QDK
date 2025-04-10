import sys
import os
import logging
import subprocess
import shutil
import sqlite3
import csv
import codesigning_common
from codesigning_common import data_to_string

def check_qpkg_conf(kwargs):
    # Check if qpkg.cfg exists, and read paramaters from it

    qpkg_conf = os.path.join(kwargs["cwd"],"qpkg.cfg")
    if not os.path.isfile(qpkg_conf):
        logging.error("Cannot find qpkg.cfg")
        sys.exit(codesigning_common.CONF_ERROR)
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
        sys.exit(codesigning_common.CONF_ERROR)
    if kwargs["version"] == "":
        logging.error("Cannot find QPKG_VER in qpkg.cfg")
        sys.exit(codesigning_common.CONF_ERROR)

def create_db(kwargs):
    kwargs["codesigning_folder"] = os.path.join(kwargs["cwd"],kwargs["buildpath"],".qcodesigning")
    kwargs["db"] = kwargs["codesigning_folder"] + "/" + codesigning_common.DB_NAME
    codesigning_common.create_db(kwargs["db"])

def update_db_by_csv(kwargs):
    # Get paths,packages from csv and insert/update DB
    sql_insert_path = "INSERT INTO SignedFile (Path, Package) VALUES (?, ?);"
    rows = codesigning_common.read_csv(kwargs["csv"])
    conn = sqlite3.connect(kwargs["db"])
    cur = conn.cursor()
    for row in rows:
        if row[0] == "":
            package = kwargs["qpkgname"]
        else:
            package = row[0]
        relative_path = row[1]
        if row[2] == "":
            absolute_path = relative_path
        else:
            absolute_path = row[2]
        cur.execute(sql_insert_path, (absolute_path, package))
    conn.commit()
    conn.close()

def create_tgz(kwargs):
    # Copy files into temp_folder and then create tgzs
    # Check if temporary folder or tgz file exists already
    temp_folder = kwargs["codesigning_folder"] + "/tgz"
    output_tgz_file = temp_folder + ".tgz"
    codesigning_common.check_for_tgz(temp_folder,output_tgz_file)

    rows = codesigning_common.read_csv(kwargs["csv"])
    # Copy files into temp folders
    for row in rows:
        relative_path = row[1]
        if row[2] == "":
            absolute_path = relative_path
        else:
            absolute_path = row[2]
        src = os.path.join(kwargs["cwd"], kwargs["srcpath"])
        src = os.path.join(src,relative_path.lstrip('/'))
        if not os.path.isfile(src):
            if (kwargs["srcpath"] != kwargs["buildpath"]):
                src1 = os.path.join(kwargs["cwd"], kwargs["srcpath"])
                src1 = os.path.join(src1,relative_path.lstrip('/'))
                if not os.path.isfile(src1):
                    logging.warning("Cannot find file " + src)
                    logging.warning("Cannot find file " + src1)
                    continue
            else:
                logging.warning("Cannot find file " + relative_path)
                continue
        dst = os.path.join(temp_folder,absolute_path.lstrip('/'))
        codesigning_common.copy_file(src, dst)
    codesigning_common.create_tgz(temp_folder,output_tgz_file)

def sign_and_update_signature(kwargs):
    # Send tar files to server, and then update signatures to DBs
    kwargs["tgzfile"] = kwargs["codesigning_folder"] + "/tgz.tgz"
    server_response = codesigning_common.sign_files(kwargs)
    codesigning_common.update_signatures(kwargs, server_response)
    os.remove(kwargs["tgzfile"])

def save_certificate(kwargs):
    pem_file_name = kwargs["codesigning_folder"] + "/" + codesigning_common.CERT_NAME
    conn = sqlite3.connect(kwargs["db"])
    cur = conn.cursor()
    sql = "SELECT Cert FROM Certificate LIMIT 1;"
    cur.execute(sql)
    entry = cur.fetchone()
    pem = entry[0]
    pem_file = open(pem_file_name, "w")
    pem_file.write(pem)
    pem_file.close()

def sign_and_save_db_signature(kwargs):
    # Generate tgz
    temp_folder = kwargs["codesigning_folder"] + "/db"
    output_tgz_file = temp_folder + ".tgz"
    codesigning_common.check_for_tgz(temp_folder,output_tgz_file)
    shutil.copyfile(kwargs["db"], temp_folder + "/" + os.path.basename(kwargs["db"]))
    codesigning_common.create_tgz(temp_folder, output_tgz_file)

    # Send to server
    kwargs["tgzfile"] = output_tgz_file
    response = codesigning_common.sign_files(kwargs)
    if response["error"] != 0:
        logging.error("Error message from server when signing codesigning DB: %s" % response["msg"])
        logging.error("DB at %s" % kwargs["db"])
        sys.exit(codesigning_common.SERVER_ERROR)
    os.remove(output_tgz_file)
    signature_b64 = response["signatures"][0]["signature"]
    signature = codesigning_common.b64_decode(signature_b64)

    # Save to file
    signature_file_name = kwargs["codesigning_folder"] + "/" + codesigning_common.DB_SIG_NAME
    signature_file = open(signature_file_name, "w+b")
    signature_file.write(signature)
    signature_file.close()

def verify_result(kwargs):
    db = 0
    db_sig = 0
    cert = 0
    dirs = os.listdir(kwargs["codesigning_folder"])
    for file in dirs:
        if os.path.isdir(file):
            logging.error("folder %s should not exist, please check csv file and code_signing.log" % file)
            sys.exit(1)
        if (file == codesigning_common.DB_NAME):
            db += 1
        elif (file == codesigning_common.DB_SIG_NAME):
            db_sig += 1
        elif (file == codesigning_common.CERT_NAME):
            cert += 1
        else:
            logging.error("file %s should not exist, please check csv file and code_signing.log" % file)
            sys.exit(1)
    if (db != 1) or (db_sig != 1) or (cert != 1):
        logging.error("something goes wrong, please check csv file and code_signing.log")
        sys.exit(1)

def print_usage():
    usage_string = """
    Usage:
        python codesigning-qpkg.py server=x.x.x.x:port cwd=working_directory csv=csv_file.csv
        cert=certificate.pem buildpath=build key_ver=key_version
        working directory: the folder where QPKG developers run qbuild / build.sh
        buildpath: The path where all source files are compressed to tar-ball
        cert: certificate of code signing server (optional)
        srcpath: The root path of source files listed in csv file (optional)
        key_type: indicate if it is qpkg or qfix (optional, default is qpkg)
        key_ver: version of key used for signing (optional)
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
    if "server" not in kwargs or "cwd" not in kwargs or \
            "csv" not in kwargs or "buildpath" not in kwargs or \
            (len(kwargs) != 4 and len(kwargs) != 5 and len(kwargs) != 6 and len(kwargs) != 7 and len(kwargs) != 8):
        print_usage()
        sys.exit(1)
    codesigning_common.check_args(kwargs)
    kwargs["token"] = codesigning_common.get_token()
    #kwargs["key_type"] = "qpkg"
    codesigning_common.check_cwd(kwargs)
    codesigning_common.check_build(kwargs)
    if "srcpath" not in kwargs or kwargs["srcpath"] == "":
        kwargs["srcpath"] = kwargs["buildpath"]
    check_qpkg_conf(kwargs)
    create_db(kwargs)
    update_db_by_csv(kwargs)
    create_tgz(kwargs)
    sign_and_update_signature(kwargs)
    save_certificate(kwargs)
    sign_and_save_db_signature(kwargs)
    verify_result(kwargs)
