# Redirect main domain subdomains onto main domain over HTTPS.
server {
	listen       80;
	listen       [::]:80;
	server_name  theportalwiki.com theportalwiki.net portal.biringa.com *.theportalwiki.net *.portal.biringa.com *.theportalwiki.com;
	rewrite      ^ https://theportalwiki.com$uri permanent;
}
