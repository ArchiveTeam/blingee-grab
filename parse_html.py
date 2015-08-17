import sys
import requests
import os
from lxml import etree


def main():
    #print sys.argv
    the_file = sys.argv[1]
    pattern = sys.argv[2]
    if len(sys.argv) > 3:
        index = sys.argv[3]
    else:
        index = False
    tries = 0
    html = open(the_file, "r").read()
    myparser = etree.HTMLParser(encoding="utf-8")
    tree = etree.HTML(html, parser=myparser)
    urls = tree.xpath(pattern)
    if urls and html:
        if index != False:
            print tree.xpath(pattern)[int(index)]
        else:
            print tree.xpath(pattern)
    else:
        print ""

if __name__ == '__main__':
    main()
