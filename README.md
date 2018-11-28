# Overview

* Build a docker image based on mcr.microsoft.com/mssql/server
* Configure the database with a database and user

# How to Run
## Clone this repo
```
git clone https://github.com/mcmoe/mssqldocker.git
```

## From DockerHub
The latest image is available on DockerHub
```
https://hub.docker.com/r/mcmoe/mssqldocker/
```

If you just want to use the image, you only need the `docker-compose.yml`.

Pulling the image
```
docker-compose pull mcmoe/mssqldocker
```

/!\ Look at the available tags on DockerHub if you would like to use a specific version

## Building the image for the first time
If you want to modify the files in the image, then you'll have to build locally.

Build with `docker-compose`:
```
docker-compose build
```

## Running the container

Modify the env variables to your liking in the `docker-compose.yml`.

Then spin up a new container using `docker-compose`
```
docker-compose up
```

Note: MSSQL passwords must be at least 8 characters long, contain upper case, lower case and digits.  
Configuration of the server will occur once it runs; the MSSQL* env variables are required for this step.

Note: add a `-d` to run the container in background

## Connecting to the container
To connect to the SQL Server in the container, you can docker exec with sqlcmd.
```
docker exec -it mssqldev /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P $SA_PASSWORD
```

## Inheriting from the image
You might want to inherit from the image and build your own in order to carry out more provisioning.
One example would be to import data into the database once it's setup.
To do so, in your docker file start with `FROM mcmoe/mssqldocker:latest`.
Then inject your command using `CMD`; it will ovveride the `CMD` in this image.
Currently, the `CMD` calls a tail on the logs to trap the process.
If you override it, you will have to worry about keeping the container running.

That's it!

# Detailed Explanation
Here's a detailed look at each of the files in the project.  

## docker-compose.yml

Simplifies the container build and run by organizing the ports and environment into the YAML file.  
You can then simple call `docker-compose up` instead of the long `docker run...` command.  

## Dockerfile
The Dockerfile defines how the image will be built.  Each of the commands in the Dockerfile is described below.

The Dockerfile defines the base image (the first layer) using the official Microsoft SQL Server Linux image that can be found on [Docker Hub](http://hub.docker.com/r/microsoft/mssql-server). The Dockerfile will pull the image with the '2019-CTP2.1-ubuntu' tag. This image requires two environment variables to be passed to it at run time - `ACCEPT_EULA` and `SA_PASSWORD`. The Microsoft SQL Server Linux image is in turn based on the official Ubuntu Linux image `Ubuntu:16.04`.

In addition, we will need to pass the following env variables `$MSSQL_DB` `$MSSQL_USER` `$MSSQL_PASSWORD`.
They will be used to configure the server with a new database and a user with admin permissions.

```
FROM mcr.microsoft.com/mssql/server:2019-CTP2.1-ubuntu
```

This RUN command creates a new directory _inside_ the container at /usr/config and then sets the working directory to that directory.

```
RUN mkdir -p /usr/config
WORKDIR /usr/config
```

Then all the source code from the project is copied into the container image in the /usr/config directory.
```
COPY . /usr/config
```

In order for the configure-db.sh script to be executable you need to run the chmod command to add +x (execute) to the file.
```
RUN chmod +x /usr/config/configure-db.sh
```

Lastly, the CMD command defines what will be executed when the container starts. In this case, it will execute the entrypoint.sh script contained in the source code for this project. The source code including the entrypoint.sh is contained in the /usr/config directory which has also been made the working directory by the commands above.
```
CMD /bin/bash ./entrypoint.sh
```

## entrypoint.sh
The entrypoint.sh script is executed when the container first starts.  The script kicks off three things _simultaneously_:
* Start SQL Server using the sqlservr.sh script (that's what the base image calls). This script will look for the existence of the `ACCEPT_EULA` and `SA_PASSWORD` environment variables. Since this will be the first execution of SQL Server the SA password will be set and then the sqlservr process will be started. Note: Sqlservr runs as a process inside of a container, _not_ as a daemon.
* Executes the configure-db.sh script contained in the source code of this project. The configure-db.sh script creates a database and a user for it with admin permissions.
* Trap the process to keep the docker container running by tailing the setup logs  

```
/opt/mssql/bin/sqlservr.sh &
/usr/config/configure-db.sh
tail -f /var/opt/mssql/log/setup*.log
```
Note: this will need the `$MSSQL_DB` `$MSSQL_USER` `$MSSQL_PASSWORD` environment variables to be set.

## configure-db.sh

We delay the execution of the configuration until the server startup is complete.
We do so by grepping on the setup logs and waiting for the `Server setup is completed` message.

```
export STATUS=0
i=0
while [[ $STATUS -eq 0 ]] || [[ $i -lt 30 ]]; do
	sleep 1
	i=$i+1
	STATUS=$(grep 'Server setup is completed' /var/opt/mssql/log/setup*.log | wc -l)
done
```
To pass the configration parameters to sqlcmd, a workaround is required that echos the parameters into a new file and then appends the original setup sql configuration into this new file. This is due to the fact that it deemed impossible to use the `-v` option to pass in parameters.

```
echo :setvar MSSQL_DB $MSSQL_DB > param_setup.sql
echo :setvar MSSQL_USER $MSSQL_USER > param_setup.sql
echo :setvar MSSQL_PASSWORD $MSSQL_PASSWORD > param_setup.sql
cat setup.sql >> param_setup.sql
```

The next command uses the SQL Server command line utility sqlcmd to execute some SQL commands contained in the newly created param_setup file.

```
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P Your_SA_Password -d master -i param_setup.sql
```

The setup.sql script will create a new database based on the env variable `$MSSQL_DB` and a user based on`$MSSQL_USER` with password `$MSSQL_PASSWORD` in the default `dbo` schema.  

## setup.sql
The setup.sql defines SQL commands to create a database along with a user login with admin permissions.  
```
CREATE DATABASE $MSSQL_DB;
GO
USE $MSSQL_DB;
GO
CREATE LOGIN $MSSQL_USER WITH PASSWORD = '$MSSQL_PASSWORD';
GO
CREATE USER $MSSQL_USER FOR LOGIN $MSSQL_USER;
GO
ALTER SERVER ROLE sysadmin ADD MEMBER [$MSSQL_USER];
GO

```
