all: sqlite3 libsqlite3.so

sqlite3: shell.c sqlite3.c sqlite3ext.h  sqlite3.h
	gcc shell.c sqlite3.c -lpthread -ldl -o $@

libsqlite3.so: sqlite3.c sqlite3ext.h  sqlite3.h
	gcc sqlite3.c -lpthread -ldl -fPIC -shared -o $@
