# encoding=utf8
import datetime
from distutils.version import StrictVersion
import hashlib
import os.path
import random
from seesaw.config import realize, NumberConfigValue
from seesaw.item import ItemInterpolation, ItemValue
from seesaw.task import SimpleTask, LimitConcurrent
from seesaw.tracker import GetItemFromTracker, PrepareStatsForTracker, \
    UploadWithTracker, SendDoneToTracker
import shutil
import socket
import subprocess
import sys
import time
import string
import requests
from lxml import etree

import seesaw
from seesaw.externalprocess import WgetDownload
from seesaw.pipeline import Pipeline
from seesaw.project import Project
from seesaw.util import find_executable


# check the seesaw version
if StrictVersion(seesaw.__version__) < StrictVersion("0.8.5"):
    raise Exception("This pipeline needs seesaw version 0.8.5 or higher.")


###########################################################################
# Find a useful Wget+Lua executable.
#
# WGET_LUA will be set to the first path that
# 1. does not crash with --version, and
# 2. prints the required version string
WGET_LUA = find_executable(
    "Wget+Lua",
    ["GNU Wget 1.14.lua.20130523-9a5c"],
    [
        "./wget-lua",
        "./wget-lua-warrior",
        "./wget-lua-local",
        "../wget-lua",
        "../../wget-lua",
        "/home/warrior/wget-lua",
        "/usr/bin/wget-lua"
    ]
)

if not WGET_LUA:
    raise Exception("No usable Wget+Lua found.")

def base36_encode(n):
    """
    Encode integer value `n` using `alphabet`. The resulting string will be a
    base-N representation of `n`, where N is the length of `alphabet`.

    Copied from https://github.com/benhodgson/basin/blob/master/src/basin.py
    """
    alphabet="0123456789abcdefghijklmnopqrstuvwxyz"
    if not (isinstance(n, int) or isinstance(n, long)):
        raise TypeError('value to encode must be an int or long')
    r = []
    base  = len(alphabet)
    while n >= base:
        r.append(alphabet[n % base])
        n = n / base
    r.append(str(alphabet[n % base]))
    r.reverse()
    return ''.join(r)

###########################################################################
# The version number of this pipeline definition.
#
# Update this each time you make a non-cosmetic change.
# It will be added to the WARC files and reported to the tracker.
VERSION = "20150820.01"
TRACKER_ID = 'blingee'
TRACKER_HOST = 'tracker.archiveteam.org'
# Number of blingees per item
NUM_BLINGEES = 100
# Number of profiles per item
NUM_PROFILES = 10

USER_AGENTS = ['Mozilla/5.0 (Windows NT 6.3; rv:24.0) Gecko/20100101 Firefox/39.0',
               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:25.0) Gecko/20100101 Firefox/39.0',
               'Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; AS; rv:11.0) like Gecko',
               'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)',
               'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
               'Opera/9.80 (Windows NT 6.0; rv:2.0) Presto/2.12.388 Version/12.16',
               'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.155 Safari/537.36']
USER_AGENT = random.choice(USER_AGENTS)
REQUESTS_HEADERS = {"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"}

###########################################################################
# This section defines project-specific tasks.
#
# Simple tasks (tasks that do not need any concurrency) are based on the
# SimpleTask class and have a process(item) method that is called for
# each item.
class CheckIP(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "CheckIP")
        self._counter = 0

    def process(self, item):
        # NEW for 2014! Check if we are behind firewall/proxy
        if self._counter <= 0:
            item.log_output('Checking IP address.')
            ip_set = set()

            ip_set.add(socket.gethostbyname('twitter.com'))
            ip_set.add(socket.gethostbyname('facebook.com'))
            ip_set.add(socket.gethostbyname('youtube.com'))
            ip_set.add(socket.gethostbyname('microsoft.com'))
            ip_set.add(socket.gethostbyname('icanhas.cheezburger.com'))
            ip_set.add(socket.gethostbyname('archiveteam.org'))

            if len(ip_set) != 6:
                item.log_output('Got IP addresses: {0}'.format(ip_set))
                item.log_output(
                    'Are you behind a firewall/proxy? That is a big no-no!')
                raise Exception(
                    'Are you behind a firewall/proxy? That is a big no-no!')

        # Check only occasionally
        if self._counter <= 0:
            self._counter = 10
        else:
            self._counter -= 1


class PrepareDirectories(SimpleTask):
    def __init__(self, warc_prefix):
        SimpleTask.__init__(self, "PrepareDirectories")
        self.warc_prefix = warc_prefix

    def process(self, item):
        item_name = item["item_name"]
        escaped_item_name = item_name.replace(':', '_').replace('/', '_').replace('~', '_')
        dirname = "/".join((item["data_dir"], escaped_item_name))

        if os.path.isdir(dirname):
            shutil.rmtree(dirname)

        os.makedirs(dirname)

        item["item_dir"] = dirname
        item["warc_file_base"] = "%s-%s-%s" % (self.warc_prefix, escaped_item_name,
            time.strftime("%Y%m%d-%H%M%S"))

        open("%(item_dir)s/%(warc_file_base)s.warc.gz" % item, "w").close()


class MoveFiles(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "MoveFiles")

    def process(self, item):
        # NEW for 2014! Check if wget was compiled with zlib support
        if os.path.exists("%(item_dir)s/%(warc_file_base)s.warc" % item):
            raise Exception('Please compile wget with zlib support!')

        os.rename("%(item_dir)s/%(warc_file_base)s.warc.gz" % item,
              "%(data_dir)s/%(warc_file_base)s.warc.gz" % item)

        shutil.rmtree("%(item_dir)s" % item)


def get_hash(filename):
    with open(filename, 'rb') as in_file:
        return hashlib.sha1(in_file.read()).hexdigest()


CWD = os.getcwd()
PIPELINE_SHA1 = get_hash(os.path.join(CWD, 'pipeline.py'))
LUA_SHA1 = get_hash(os.path.join(CWD, 'blingee.lua'))


def stats_id_function(item):
    # NEW for 2014! Some accountability hashes and stats.
    d = {
        'pipeline_hash': PIPELINE_SHA1,
        'lua_hash': LUA_SHA1,
        'python_version': sys.version,
    }

    return d


class WgetArgs(object):
    def realize(self, item):
        wget_args = [
            WGET_LUA,
            "-U", USER_AGENT,
            "--header", "Accept-Language: en-US,en;q=0.8",
            "-nv",
            "--lua-script", "blingee.lua",
            "-o", ItemInterpolation("%(item_dir)s/wget.log"),
            "--no-check-certificate",
            "--output-document", ItemInterpolation("%(item_dir)s/wget.tmp"),
            "--truncate-output",
            "-e", "robots=off",
            "--rotate-dns",
            "--no-cookies",
            "--no-parent",
            "--timeout", "30",
            "--tries", "inf",
            "--domains", "blingee.com,s3.amazonaws.com,image.blingee.com,image.blingee.com.s3.amazonaws.com",
            "--span-hosts",
            "--waitretry", "30",
            "--warc-file", ItemInterpolation("%(item_dir)s/%(warc_file_base)s"),
            "--warc-header", "operator: Archive Team",
            "--warc-header", "blingee-dld-script-version: " + VERSION,
            "--warc-header", ItemInterpolation("blingee: %(item_name)s")
        ]

        item_name = item['item_name']
        assert ':' in item_name
        item_type, item_value = item_name.split(':', 1)

        item['item_type'] = item_type
        item['item_value'] = item_value

        assert item_type in ('blingee',
                             'stamp',
                             'group',
                             'competition',
                             'challenge',
                             'badge',
                             'profile')

        if item_type == 'blingee':
            for val in xrange(int(item_value), int(item_value)+NUM_BLINGEES):
                wget_args.append("http://blingee.com/blingee/view/{0}".format(val))
                wget_args.append("http://blingee.com/blingee/{0}/comments".format(val))
                wget_args.append("http://bln.gs/b/{0}".format(base36_encode(val)))
        elif item_type == 'stamp':
            wget_args.append("http://blingee.com/stamp/view/{0}".format(item_value))
        elif item_type == 'group':
            wget_args.extend(["--recursive", "--level=inf"])
            wget_args.append("http://blingee.com/group/{0}".format(item_value))
            wget_args.append("http://blingee.com/group/{0}/members".format(item_value))
        elif item_type == 'competition':
            wget_args.append("http://blingee.com/competition/view/{0}".format(item_value))
            wget_args.append("http://blingee.com/competition/rankings/{0}".format(item_value))
        elif item_type == 'challenge':
            wget_args.append("http://blingee.com/challenge/view/{0}".format(item_value))
            wget_args.append("http://blingee.com/challenge/rankings/{0}".format(item_value))
        elif item_type == 'badge':
            wget_args.append("http://blingee.com/badge/view/{0}".format(item_value))
            wget_args.append("http://blingee.com/badge/winner_list/{0}".format(item_value))
        elif item_type == 'profile':
            for val in xrange(int(item_value), int(item_value)+NUM_PROFILES):
                print("Getting username for ID {0}...".format(val))
                sys.stdout.flush()
                tries = 0
                while tries < 50:
                    url = "http://blingee.com/badge/view/42/user/{0}".format(val)
                    html = requests.get(url, headers=REQUESTS_HEADERS)
                    if html.status_code == 200 and html.text:
                        myparser = etree.HTMLParser(encoding="utf-8")
                        tree = etree.HTML(html.text, parser=myparser)
                        links = tree.xpath('//div[@id="badgeinfo"]//a/@href')
                        username = [link for link in links if "/profile/" in link]
                        if not username:
                            print("Skipping deleted/private profile.")
                            break
                        else:
                            username = username[0]
                            wget_args.append("http://blingee.com{0}".format(username))
                            wget_args.append("http://blingee.com{0}/statistics".format(username))
                            wget_args.append("http://blingee.com{0}/circle".format(username))
                            wget_args.append("http://blingee.com{0}/badges".format(username))
                            wget_args.append("http://blingee.com{0}/comments".format(username))
                            print("Username is {0}".format(username.replace("/profile/", "")))
                            sys.stdout.flush()
                            break
                    else:
                        print("Got status code {0}, sleeping...".format(html.status_code))
                        sys.stdout.flush()
                        time.sleep(5)
                        tries += 1

        else:
            raise Exception('Unknown item')

        if 'bind_address' in globals():
            wget_args.extend(['--bind-address', globals()['bind_address']])
            print('')
            print('*** Wget will bind address at {0} ***'.format(
                  globals()['bind_address']))
            print('')

        return realize(wget_args, item)

###########################################################################
# Initialize the project.
#
# This will be shown in the warrior management panel. The logo should not
# be too big. The deadline is optional.
project = Project(
    title="blingee",
    project_html="""
        <img class="project-logo" alt="Project logo" src="http://archiveteam.org/images/6/6e/Blingee_logo.png" height="50px" title=""/>
        <h2>blingee.com <span class="links"><a href="http://blingee.com/">Website</a> &middot; <a href="http://tracker.archiveteam.org/blingee/">Leaderboard</a></span></h2>
        <p>Saving all images and content from Blingee.</p>
    """,
    utc_deadline=datetime.datetime(2015, 8, 25, 0, 0, 0)
)

pipeline = Pipeline(
    CheckIP(),
    GetItemFromTracker("http://%s/%s" % (TRACKER_HOST, TRACKER_ID), downloader,
        VERSION),
    PrepareDirectories(warc_prefix="blingee"),
    WgetDownload(
        WgetArgs(),
        max_tries=2,
        accept_on_exit_code=[0, 4, 8],
        env={
            "item_dir": ItemValue("item_dir"),
            "item_value": ItemValue("item_value"),
            "item_type": ItemValue("item_type"),
        }
    ),
    PrepareStatsForTracker(
        defaults={"downloader": downloader, "version": VERSION},
        file_groups={
            "data": [
                ItemInterpolation("%(item_dir)s/%(warc_file_base)s.warc.gz")
            ]
        },
        id_function=stats_id_function,
    ),
    MoveFiles(),
    LimitConcurrent(NumberConfigValue(min=1, max=4, default="1",
        name="shared:rsync_threads", title="Rsync threads",
        description="The maximum number of concurrent uploads."),
        UploadWithTracker(
            "http://%s/%s" % (TRACKER_HOST, TRACKER_ID),
            downloader=downloader,
            version=VERSION,
            files=[
                ItemInterpolation("%(data_dir)s/%(warc_file_base)s.warc.gz")
            ],
            rsync_target_source_path=ItemInterpolation("%(data_dir)s/"),
            rsync_extra_args=[
                "--recursive",
                "--partial",
                "--partial-dir", ".rsync-tmp",
            ]
            ),
    ),
    SendDoneToTracker(
        tracker_url="http://%s/%s" % (TRACKER_HOST, TRACKER_ID),
        stats=ItemValue("stats")
    )
)
