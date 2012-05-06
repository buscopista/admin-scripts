admin-scripts
=============

Set of scripts to administer the site, from backups to database deltas.
All the scripts that are little enought to not be a project for its own.


aux/config.sh (library)
-------------
This script provides the functions to handle and parse configuration files from bash scripts. The main functions are:

**conf::load** conf_file

>Load a configuration file in the format `key=value`. The `key`will be adated to a bash variable name, changing all the not valid chars for underscores '_'. Also follows include tags.   
> A sample 3 config files setup:  

> _/etc/myapp/myconf.cfg_

>     defaultvar = defaultvalue
>     myvar1 = mydefaultvalue1

>_/etc/myapp/myconf.cfg_

>     include /etc/myapp/mydefaultconfig.cfg
>     myvar1 = myvalue1
>     myvár2 = 'my value 2'
>     my var 3 = my value 3
>     include ~/.my_user_conf.cfg
    
>_~/.my_user_conf.cfg_

>     my_var_3 = peruservalue3                                                       
                                                                                   
                                                                                
>Then if you load this config you'll end up whith this varaibles defined (as seen with `set`):  

>     defaultvar=defaultvalue
>     myvar1=myvalue1
>     myv_r2=''\''my value 2'\'''
>     my_var_3=peruservalue3

                                                                                
**conf::require** [var1 [var2 [...] ] ]
> Once loaded the configuration this function provides an easy way of checking what varaibes are missing (and will show a freandly message of what variables are not defined).  
>For example, after doing the above load this call:

>     >$ conf::require myvar1 notconfgured1 notconfigured2

> Will show the messages:

>     Required parameter notconfgured1 not found in the config file.
>     Required parameter notconfigured2 not found in the config file.


aux/log.sh (library)
-------------
This file is used to show pretty log messages (with ansi colors and timestamps). Four functions are provided:

**< log | log::INFO > [message [...]]**  
> Those functions show an INFO message, in blue.

**log:WARN [message [...]]**  
>This function will show a warning message in yellow.

**log:ERROR [message [...]]**  
>This one will show an error message in red.

**log::OK [message [...]]**  
>This last one, will show an info message (in blue) but with the text in green. Very handy in those cases when you must show a 'Done' or 'OK' message ;)


db.sh [-h] [-d] [-c conf_file] command
------------
This script is used to backup, restore and update the database.
Keeps track of the updates using a table on the destination database, with the name of the `deltas_table` defined in the configuration file (see the above config functions).  
The available commands are:
**backup [user|sys|all]**
>Do a backup of the user generated, system or all tables (will use all by default). The user generated tables are defined with the `user_tables` variable, and is empty by default.  
>Example:

>     >$ ./db.sh backup all

**restore [-d] [-l [user|sys|all] | file]**
>Restore a backup, using the last generetaed backup (all the tables by default) with the `backup` command or a given sql file. The `-d` flag drops the destination database before restoring the backup.  
**Be careful using the `-d` flag**: if you only restore some of the tables, all the other tables will be dropped.  
Example:

>     >$ ./db.sh restore -l sys

**update [delta1 [...]]**
>Applies the given sql scripts and registers them in the database. The scripts (called _deltas_) meust have the name _IDNUMBER-Comment.sql_ where _IDNUMBER_ is a number identifying the script (two scripts with the same _IDNUMBER_ are treated as the same). There's no way of undoing the scripts other than applying a new sql script written for that propose, sorry... (Hopefully in the future something fancier can be figured out).

files.sh
-------------
This scripts handles the backup, restoration and update of the files.
TODO

