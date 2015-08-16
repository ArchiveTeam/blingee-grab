import sys
import requests
import os

def main():
    url = sys.argv[1]
    tries = 0
    if os.path.isfile('302file'):
        os.remove('302file')
    while tries < 6:
#        print("Fetching {1}, try {0}".format(tries + 1, url))
#        sys.stdout.flush()
        html = requests.get(url)
        if html.status_code == 200 and html.text:
#            print("Succes!")
#            sys.stdout.flush()
            redirfile = open('302file', 'w')
            for redirurl in html.history:
                redirfile.write(redirurl.url + "\n")
#                print(redirurl.url)
#                sys.stdout.flush()
            redirfile.write(html.url)
#            print(html.url)
#            sys.stdout.flush()
            redirfile.close()
            break
        elif html.status_code == 404:
#            print("Succes!")
#            sys.stdout.flush()
            redirfile = open('302file', 'w')
            redirfile.write(html.url + "\n")
            redirfile.write(html.url)
#            print(html.url)
#            sys.stdout.flush()
            redirfile.close()
            break
        print("Received status code {0}, retrying to fetch url".format(html.status_code))
        sys.stdout.flush()
        tries = tries + 1
    if tries == 6:
        print("Exception fetching {0}".format(url))
        sys.stdout.flush()
        raise Exception

if __name__ == '__main__':
    main()
