import sys
import requests
from lxml import etree

def main():
    #print sys.argv
    the_file = sys.argv[1]
    pattern = sys.argv[2]
    if len(sys.argv) > 3:
        index = sys.argv[3]
    else:
        index = False
    html = ""
    while True:
        try:
            f = open(the_file, "r")
            html = f.read()
            f.close()
            break
        except EnvironmentError:
            # Hit the limit of file descriptors, etc.
            continue
    if html:
        myparser = etree.HTMLParser(encoding="utf-8")
        tree = etree.HTML(html, parser=myparser)
        urls = tree.xpath(pattern)
        if urls and html:
            if index != False:
                print urls[int(index)]
            else:
                print urls
        else:
            print "none"
    else:
        print "none"

if __name__ == '__main__':
    main()
