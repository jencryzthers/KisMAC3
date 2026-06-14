#!/usr/bin/env python3
import sys
import os
import urllib.request
import time


kOUIWebFilePath = 'https://standards-oui.ieee.org/oui.txt'
kOUITempFilePath = '/tmp/OUI.txt'
kOUILocalFileName = 'Resources/Generic/vendor.db'
kPlistTemplateFileName = 'Resources/Generic/plistTemplate.tmp'

def xcodePrint(string):
	print(string)
	sys.stdout.flush()

def needForce(filename):
	configuration = os.getenv("CONFIGURATION")
	if configuration == 'Release':
		return True

	if (os.path.exists(filename)):
		fileCreation = os.path.getctime(filename)
		now = time.time()
		days_ago = now - 60*60*24*7 # Number of seconds in seven days
		return fileCreation < days_ago

	return False

def downloadFile(fileurl, filename):
	request = urllib.request.Request(fileurl)
	response = urllib.request.urlopen(request, timeout=30)
	# Retrieve file size
	metainfo = response.info()
	filesize = int(metainfo.get("Content-Length", "0"))
	xcodePrint('Downloading file: %s Size: %s' % (filename, filesize))

	fileBundle = open(filename, 'wb')
	latest_progress = -1
	downloaded = 0
	chunksize = 8192
	while True:
		buffer = response.read(chunksize)
		if not buffer:
			break

		downloaded += len(buffer)

		if filesize:
			# show progress each 10% completed
			progress = int((downloaded * 100.0 / filesize) / 10)
			if (latest_progress != progress):
				latest_progress = progress
				xcodePrint('%s%%' % (progress * 10))

		fileBundle.write(buffer)

	fileBundle.close()
	# check downloaded size
	statinfo = os.stat(filename)
	return (filesize == 0 or filesize == statinfo.st_size)

def parseVendors(srcName, dstName):
	inputfile = open(srcName, 'r')
	outputfile = open(dstName, 'w')
	plistTemplateFile = open(kPlistTemplateFileName, 'r')

	data = inputfile.read()
	entries = data.split("\n\n")[6:-2] #ignore first and last entries, they're not real entries

	plistTemplateData = plistTemplateFile.read()

	outputfile.write(plistTemplateData)

	d = {}
	for entry in entries:
		parts = entry.split("\n")[0].split("\t")
		print(parts[0])
		company_id = parts[0].split()[0]
		company_id = company_id.replace('-', ':')
		company_name = parts[-1]
		company_name = company_name.replace('&', 'And')
		outputfile.write('\n\t')
		key = '<key>' + company_id + '</key>\n\t<string>' + company_name + '</string>'
		outputfile.write(key)

	outputfile.write('\n</dict>\n</plist>\n')

def writeEmptyVendorDB(dstName):
	plistTemplateFile = open(kPlistTemplateFileName, 'r')
	outputfile = open(dstName, 'w')
	outputfile.write(plistTemplateFile.read())
	outputfile.write('\n</dict>\n</plist>\n')
	outputfile.close()
	plistTemplateFile.close()

def main():
	if (not needForce(kOUILocalFileName) and os.path.exists(kOUILocalFileName)):
		xcodePrint('Vendor Database exists, skip downloading')
		sys.exit(0)
		return

	try:
		success = downloadFile(kOUIWebFilePath, kOUITempFilePath)
	except Exception as e:
		xcodePrint('Vendor database download failed: %s' % e)
		success = False

	if (success):
		parseVendors(kOUITempFilePath, kOUILocalFileName)
	elif not os.path.exists(kOUILocalFileName):
		xcodePrint('Creating an empty vendor database so the app can build offline')
		writeEmptyVendorDB(kOUILocalFileName)
		success = True

	sys.exit(not success)

main()
