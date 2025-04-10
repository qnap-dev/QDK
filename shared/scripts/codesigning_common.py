import sys
import os
import shutil
import logging
import sqlite3
import json
import tempfile
import subprocess
import csv

TOOL = "openssl"

TOKEN_NOT_SET = 2
CONNECT_ERROR = 3
SERVER_ERROR = 4

CONF_ERROR = 21
CSV_ERROR = 22

DB_NAME = "nas_sign.db"
DB_SIG_NAME = "nas_sign.sig"
CERT_NAME = "cert.pem"

def get_token():
    if "QNAP_CODESIGNING_TOKEN" not in os.environ:
        logging.error("Environment variable QNAP_CODESIGNING_TOKEN not set")
        sys.exit(TOKEN_NOT_SET)
    return os.environ["QNAP_CODESIGNING_TOKEN"]

def config_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

def check_is_db(db_file):
    try:
        conn = sqlite3.connect(db_file)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        conn.close()
    except sqlite3.DatabaseError:
        logging.error("%s is not a valid sqlite db" % db_file)
        sys.exit(1)

def check_args(kwargs):
    if "db" in kwargs and os.path.isfile(kwargs["db"]):
        check_is_db(kwargs["db"])
    if "csv" in kwargs and not os.path.isfile(kwargs["csv"]):
        logging.warning("Cannot find csv file, ignore anti-tamper")
        sys.exit(0)
    if "ca_cert" in kwargs and kwargs["ca_cert"] == "":
        logging.error("parameter ca_cert not provided")
        sys.exit(1)
    if "tgzfile" in kwargs and not os.path.isfile(kwargs["tgzfile"]):
        logging.error("cannot find tgz file %s" % kwargs["tgzfile"])
        sys.exit(1)
    if "version" in kwargs and kwargs["version"] == "":
        logging.error("version number not provided")
        sys.exit(1)
    if "key_type" not in kwargs:
        kwargs["key_type"] = "qpkg"

def check_cwd(kwargs):
    if not os.path.isdir(kwargs["cwd"]):
        logging.error("cwd %s is not a directory" % kwargs["cwd"])
        sys.exit(1)

def check_build(kwargs):
    build_path = os.path.join(kwargs["cwd"],kwargs["buildpath"])
    if not os.path.isdir(build_path):
        logging.error("buildpath %s is not a directory" % kwargs["buildpath"])
        sys.exit(1)

def create_db(db):
    sql_create_signature_table = """
        CREATE TABLE SignedFile (
            FileID INTEGER PRIMARY KEY,
            Path TEXT NOT NULL,
            Package TEXT,
            Signature BLOB,
            CertID INT
        );
    """
    sql_add_path_index = "CREATE INDEX SignedFilePath ON SignedFile (Path);"
    if TOOL == "openssl": 
        sql_create_key_table = """
            CREATE TABLE Certificate (
                CertID INTEGER PRIMARY KEY,
                Type TEXT NOT NULL,
                QpkgName TEXT,
                Cert TEXT NOT NULL,
                DigitalSignature TEXT
            );
        """
    elif TOOL == "gpg":
        sql_create_key_table = """
            CREATE TABLE Certificate (
                CertID INTEGER PRIMARY KEY,
                Type TEXT NOT NULL,
                QpkgName TEXT,
                Cert BLOB NOT NULL,
                DigitalSignature TEXT
            );
        """

    db_folder = os.path.dirname(db)
    if db_folder != "" and not os.path.isdir(db_folder):
        try:
            os.makedirs(db_folder)
        except Exception as e:
            logging.error(str(e) + " when creating folder %s" % db_folder)
            sys.exit(1)
    if os.path.isfile(db):
        try:
            os.remove(db)
        except Exception as e:
            logging.error(str(e) + " when removing file %s" % db)
            sys.exit(1)
    conn = sqlite3.connect(db)
    cur = conn.cursor()
    cur.execute(sql_create_signature_table)
    cur.execute(sql_add_path_index)
    cur.execute(sql_create_key_table)
    conn.commit()
    conn.close()

def data_to_string(data):
    ret = ''
    if isinstance(data, str):
        ret = data
    else:
        ret = data.decode('utf-8')
    return ret

def read_csv(csv_file):
    try:
        with open(csv_file, 'r') as f:
            reader = csv.reader(f)
            output = []
            for row in reader:
                try:
                    if len(row) == 0: # empty line
                        continue
                    if (row[0] != "" and row[0] != "\xef\xbb\xbf"):
                        package = data_to_string(row[0]).strip()
                        if package != "" and package[0] == "#": # a line of comment
                            continue
                    else:
                        package = ""
                    if len(row) < 3: # less than 3 items, wrong format, treat it as error
                        logging.error("Line '%s' in csv has less than 3 columns" % ','.join(row))
                        sys.exit(CSV_ERROR)
                    if (row[1] != "" and row[1] != "\xef\xbb\xbf"):
                        relative_path = data_to_string(row[1]).strip()
                    else:
                        relative_path = ""
                    if (row[2] != "" and row[2] != "\xef\xbb\xbf"):
                        absolute_path = data_to_string(row[2]).strip()
                    else:
                        absolute_path = ""
                    output.append([package,relative_path,absolute_path])
                except UnicodeDecodeError as decode_error:
                    logging.error(str(decode_error) + " when decoding line")
                    sys.exit(CSV_ERROR)
            return output
    except Exception as e:
        logging.error(str(e) + " when processing csv")
        sys.exit(1)

def update_packages(db, csv_file):
    # Get paths,packages from csv and insert/update DB
    rows = read_csv(csv_file)

    sql_insert_path = """INSERT INTO SignedFile (Path, Package) SELECT ?, ?
                         WHERE NOT EXISTS (SELECT 1 FROM SignedFile WHERE Path = ?);
    """
    sql_update_package = "UPDATE SignedFile SET Package = ? WHERE Path = ?"

    conn = sqlite3.connect(db)
    conn.text_factory = str
    cur = conn.cursor()
    for row in rows:
        if (row[0] != ""):
            package = row[0]
        else:
            package = "System"
        if (row[2] != ""):
            absolute_path = row[2]
        else:
            absolute_path = row[1]
        cur.execute(sql_insert_path, (absolute_path, package, absolute_path))
        if cur.rowcount == 0:
            # in case that path already exists in DB, update "Package" value
            cur.execute(sql_update_package, (package, absolute_path))
    conn.commit()
    conn.close()

def copy_file(src, dst):
    dst_dir = os.path.dirname(dst)
    if not os.path.exists(dst_dir):
        try:
            os.makedirs(dst_dir)
        except Exception as e:
            logging.error(str(e) + " when creating folder " + dst_dir)
            sys.exit(1)
    shutil.copyfile(src, dst)

def check_for_tgz(temp_folder, output_tgz_file):
    # Check if temp folder or tgz file exists already. Remove it if exists

    if os.path.exists(temp_folder): # if the temp folder exists already
        try:
            shutil.rmtree(temp_folder)
        except Exception as e:
            logging.error(str(e) + " when removing folder %s" % temp_folder)
            sys.exit(1)
    try:
        os.makedirs(temp_folder)
    except Exception as e:
        logging.error(str(e) + " when creating folder %s" % temp_folder)
        sys.exit(1)
    if os.path.exists(output_tgz_file): # if the tgz exists already
        try:
            os.remove(output_tgz_file)
        except Exception as e:
            logging.error(str(e) + " when removing tgz file %s" % output_tgz_file)
            sys.exit(1)

def create_tgz(temp_folder, output_tgz_file):
    # Tar the files in temp folder
    command = ["tar","-czf",output_tgz_file,"."]
    sp = subprocess.Popen(command,cwd=temp_folder,stdout=subprocess.PIPE)
    out = sp.communicate()[0]
    if sp.returncode != 0:
        logging.error(out)
        sys.exit(1)
    shutil.rmtree(temp_folder)

def sign_files(kwargs):
    # Upload tgz to code signing server, and return response from server
    server = kwargs["server"]
    key_type = kwargs["key_type"]
    tgz_file_name = kwargs["tgzfile"]
    url = "%s/sign/%s" % (server,key_type)
    if key_type == "fw":
        url = url + "/" + kwargs["version"]
    elif key_type == "qpkg":
        url = url + "/" + kwargs["qpkgname"] + "/" + kwargs["version"]
    command = ["curl",
                "-k",
                "--connect-timeout", "60",
                "--max-time", "600",
                "--retry", "3",
                "-X", "POST",
                "-F", "token=%s" % kwargs["token"],
                "-F", "file=@%s" % tgz_file_name]
    if "key_ver" in kwargs:
        command = command + ["-F","key_ver=%s" % kwargs["key_ver"]]
    command.append("https://%s" % url)
    logging.info(command)
    try:
        sp = subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        out,err = sp.communicate()
        if sp.returncode != 0:
            logging.error("curl error %s" % err)
            sys.exit(CONNECT_ERROR)
        try:
            out = out.decode()
        except (UnicodeDecodeError, AttributeError):
            pass
        response = json.loads(out)
        if response["error"] != 0:
            logging.error("Error message from server: %s" % response["msg"])
            sys.exit(SERVER_ERROR)
        return response
    except Exception as e:
        logging.error("Failed to run curl command")
        sys.exit(1)

def sign_cms(kwargs):
    server = kwargs["server"]
    key_type = kwargs["key_type"]
    file_name = kwargs["file"]
    url = "%s/signcms/%s" % (server,key_type)
    if key_type == "fw":
        url = url + "/" + kwargs["version"]
    elif key_type == "qpkg":
        url = url + "/" + kwargs["qpkgname"] + "/" + kwargs["version"]
    command = ["curl",
                "-k",
                "--connect-timeout", "60",
                "--max-time", "600",
                "--retry", "3",
                "-X", "POST",
                "-F", "token=%s" % kwargs["token"],
                "-F", "file=@%s" % file_name]
    if "key_ver" in kwargs:
        command = command + ["-F","key_ver=%s" % kwargs["key_ver"]]
    command.append("https://%s" % url)
    logging.info(command)
    try:
        sp = subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        out,err = sp.communicate()
        if sp.returncode != 0:
            logging.error("curl error %s" % err)
            sys.exit(CONNECT_ERROR)
        try:
            out = out.decode()
        except (UnicodeDecodeError, AttributeError):
            pass
        response = json.loads(out)
        if response["error"] != 0:
            logging.error("Error message from server: %s" % response["msg"])
            sys.exit(SERVER_ERROR)
        return response
    except Exception as e:
        logging.error("Failed to run curl command")
        sys.exit(1)

def b64_decode(encoded):
    encoded_file = tempfile.NamedTemporaryFile(mode="w")
    encoded_file.write(encoded)
    encoded_file.flush()
    decoded_file = tempfile.NamedTemporaryFile(mode="w+b")
    command = ["openssl","enc","-d","-base64","-A","-in",encoded_file.name,"-out",decoded_file.name]
    try:
        returncode = subprocess.call(command)
        if returncode != 0:
            logging.error("Failed to decode signature of file: %s" % path)
            sys.exit(1)
        else:
            return decoded_file.read()
    except Exception as e:
        logging.error("Failed to run openssl command: %s" % command)
        sys.exit(1)

def add_cert_to_db(certificate_dict, sqlite_file_name):
    # put this certificate into DB and get cert ID if certificate not in DB already
    # otherwise get cert ID from DB

    certid = -1
    key_type = certificate_dict["key_type"]
    qpkgname = certificate_dict["qpkgname"] if "qpkgname" in certificate_dict else ""
    if TOOL == "openssl":
        cert = certificate_dict["pem"]
    elif TOOL == "gpg":
        cert = b64_decode(certificate_dict["pem"])
    conn = sqlite3.connect(sqlite_file_name)
    cur = conn.cursor()
    sql_get_key = "SELECT * FROM Certificate WHERE Type=? AND QpkgName=?;"
    cur.execute(sql_get_key, (key_type,qpkgname))
    entry = cur.fetchone()
    if entry == None:
        # Key doesnot exist in DB, insert one and return KeyID
        sql_insert_key = "INSERT INTO Certificate (Type,QpkgName,Cert) VALUES (?,?,?);"
        if TOOL == "openssl":
            cur.execute(sql_insert_key, (key_type,qpkgname,cert))
        elif TOOL == "gpg":
            cur.execute(sql_insert_key, (key_type,qpkgname,sqlite3.Binary(cert)))
        certid = cur.lastrowid
    else:
        # Key already exists in DB, return KeyID
        certid = entry[0]
    conn.commit()
    cur.close()
    conn.close()
    return certid

def update_signatures(kwargs, server_response):
    if server_response["error"] != 0:
        logging.error("Error message from server: %s" % server_response["msg"])
        sys.exit(SERVER_ERROR)
    sqlite_file_name = kwargs["db"]
    certid = add_cert_to_db(server_response["certificate"], sqlite_file_name)
    signatures = server_response["signatures"]
    conn = sqlite3.connect(sqlite_file_name)
    cur = conn.cursor()
    sql_update_signature = "UPDATE SignedFile SET CertID=?, Signature=? WHERE Path=?"
    sql_insert_signature = "INSERT INTO SignedFile (Path,Signature,CertID) VALUES (?,?,?)"
    signatures_added = False
    for item in signatures:
        file_path = item["file"]
        signature = b64_decode(item["signature"])
        if signature is None:
            continue
        cur.execute(sql_update_signature, (certid, sqlite3.Binary(signature), file_path))
        if cur.rowcount == 0:
            # The path doesnot exist in DB, insert new one
            cur.execute(sql_insert_signature, (file_path, sqlite3.Binary(signature), certid))
        signatures_added = True
    conn.commit()
    cur.execute("DELETE FROM SignedFile WHERE Signature IS NULL;")
    conn.commit()
    cur.close()
    conn.close()
    if signatures_added:
        logging.info("Updated signatures to anti-tampering DB")
    else:
        logging.warning("No signature is added into anti-tampering DB")
