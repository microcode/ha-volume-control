import os

appcast = "gh-pages/appcast.xml"
version = os.environ["VERSION"]
pub_date = os.environ["PUB_DATE"]
download_url = os.environ["DOWNLOAD_URL"]
signature = os.environ["SIGNATURE"]
file_size = os.environ["FILE_SIZE"]

new_item = f"""        <item>
            <title>Version {version}</title>
            <pubDate>{pub_date}</pubDate>
            <enclosure
                url="{download_url}"
                sparkle:version="{version}"
                sparkle:shortVersionString="{version}"
                sparkle:edSignature="{signature}"
                length="{file_size}"
                type="application/octet-stream" />
        </item>"""

if os.path.exists(appcast):
    content = open(appcast).read()
    content = content.replace("    </channel>", new_item + "\n    </channel>", 1)
else:
    content = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>HA Volume Control</title>
        <link>https://microcode.github.io/ha-volume-control/appcast.xml</link>
{new_item}
    </channel>
</rss>
"""

open(appcast, "w").write(content)
