server {
listen 80 default_server;
root /data/www;
server_name _;
location ~ .*\.(yml|yaml|sh)$ {
    add_header Content-Type text/plain;
}
location / {
    autoindex on;
    autoindex_format html;
    autoindex_exact_size off; 
    autoindex_localtime on;
    charset utf-8,gbk;
    }
}