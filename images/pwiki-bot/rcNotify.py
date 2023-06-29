#!/usr/bin/env python
# -*- coding: utf-8 -*-
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import time #, Dr. Freeman?
import urllib, urllib2 # Series of tubes
import re # Dem regexes
import hashlib # Yummy
import pprint # prettyPrint
import wikitools # Wiki bindings
import sys # Command-line arguments parsing
import traceback # Print error stack traces

# Config:
from botConfig import rcNotifyConfig as config

# Constants:
wiki = wikitools.wiki.Wiki(config['wikiUrl'])
refreshRatePage = config['refreshRatePage']
notifyUrl = config['notifyUrl']
httpTimeout = config['httpTimeout']
# Globals:
refreshRate = config['refreshRate'] # 3 minutes by default
lastRC = -1 # Will be populated later

def u(s):
	if type(s) is type(u''):
		return s
	if type(s) is type(''):
		try:
			return unicode(s)
		except:
			try:
				return unicode(s.decode('utf8'))
			except:
				try:
					return unicode(s.decode('windows-1252'))
				except:
					return unicode(s, errors='ignore')
	try:
		return unicode(s)
	except:
		try:
			return u(str(s))
		except:
			return s
def urlEncode(s):
	encoded = urllib2.quote(urllib2.unquote(eval(u(s).encode('utf8').__repr__().replace('\\x', '%'))))
	encoded = encoded.replace('head%20', 'head_')
	encoded = encoded.replace('%7B', '').replace('%7D', '')
	return encoded
def getNotifyResponse(params):
	global notifyUrl, config, httpTimeout
	if type(params) in (type(''), type(u'')):
		params = u(params)
	else:
		params = u(urllib.urlencode(params))
	if config['via'] is not None:
		params += '&via=' + u(urlEncode(config['via']))
	print('>>> Notifying URL', notifyUrl, 'with params:', params)
	response = urllib2.urlopen(notifyUrl, params, timeout=httpTimeout).read(-1)
	print 'Response:', response
	return response
def updateRefreshRate():
	global wiki, refreshRate, refreshRatePage, config
	if type(config['refreshRate']) is type(0):
		return
	try:
		refreshRate = int(wikitools.page.Page(wiki, refreshRatePage).getWikiText())
	except:
		refreshRate = config['refreshRate']
	if type(refreshRate) is not type(0):
		print 'Error while grabbing refresh rate; defaulting to 180s.'
		refreshRate = 180
def updateLastRC(last=None):
	global lastRC
	try:
		if last is None:
			lastRC = int(getNotifyResponse('requestrcid=1'))
		else:
			lastRC = int(last)
	except:
		lastRC = -1
def reviewRC(rc):
	global lastRC
	if rc['rcid'] <= lastRC:
		return None
	pprint.PrettyPrinter(indent=4).pprint(rc)
	flag = ''
	if 'redirect' in rc:
		flag += 'R'
	if rc['type'] == u'new':
		flag += 'N'
	elif rc['type'] == u'log':
		flag += 'L'
	if 'minor' in rc:
		flag += 'm'
	if 'bot' in rc:
		flag += 'b'
	if not flag:
		flag = '-'
	params = {
		'rcid': rc['rcid'],
		'user': rc.get('user', '<UNKNOWN>'),
		'title': rc['title'],
		'pageid': rc['pageid'],
		'namespace': rc['ns'],
		'newrevid': rc['revid'],
		'oldrevid': rc['old_revid'],
		'newsize': rc['newlen'],
		'oldsize': rc['oldlen'],
		'flags': flag,
		'comment': rc.get('comment', ''),
		'timestamp': rc['timestamp']
	}
	optionalstuff = ('logtype', 'logid', 'logaction')
	for o in optionalstuff:
		if o in rc:
			params[o] = rc[o]
	return params
def multiUrlEncode(allParams):
	s = []
	c = 0
	for p in allParams:
		for k in p.keys():
			s.append(urlEncode(k) + u'_' + u(c) + u'=' + urlEncode(p[k]))
		c += 1
	return u'&'.join(s)
def checkForRCs():
	global config
	rcs = wikitools.api.APIRequest(wiki, {
			'action': 'query',
			'list': 'recentchanges',
			'rclimit': str(config['rcLimit']),
			'rcprop': 'user|comment|title|ids|timestamp|sizes|redirect|flags|loginfo'
		}).query(querycontinue=False, timeout=15)['query']['recentchanges']
	rcs.reverse() # Chronological order
	allParams = []
	for rc in rcs:
		rc = reviewRC(rc)
		if rc is not None:
			allParams.append(rc)
	allParams = allParams[:min(config['rcSubmitLimit'], len(allParams))]
	response = getNotifyResponse(multiUrlEncode(allParams))
	updateLastRC(response)
def main(once=False):
	global refreshRate, config
	updateRefreshRate()
	updateLastRC()
	print 'Started with last RCID =', lastRC
	print 'Refresh rate =', refreshRate
	once = once or '--once' in sys.argv[1:]
	while True:
		try:
			try:
				print 'Checking for RCs.'
				checkForRCs()
			except:
				print 'Error while checking for RCs.'
				traceback.print_exc()
			if once:
				print 'Exitting after only one run.'
				break
			print 'Sleeping for', refreshRate, 'seconds.'
			time.sleep(refreshRate)
		except KeyboardInterrupt:
			print 'End.'
			break
if __name__ == '__main__':
	main()
