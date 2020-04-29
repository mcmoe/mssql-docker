FROM mcr.microsoft.com/mssql/server:2019-CU4-ubuntu-16.04

# Create a config directory
RUN mkdir -p /usr/config
WORKDIR /usr/config

# Bundle config source - https://go.microsoft.com/fwlink/?linkid=2099216 - 2019 now runs as non root `mssql` user
COPY --chown=mssql:root . /usr/config

# Grant our scripts permission to be executable
RUN chmod +x /usr/config/entrypoint.sh
RUN chmod +x /usr/config/configure-db.sh

ENTRYPOINT ["./entrypoint.sh"]

# Tail the setup logs to trap the process
CMD ["tail -f /dev/null"]

HEALTHCHECK --interval=15s CMD /opt/mssql-tools/bin/sqlcmd -U sa -P $SA_PASSWORD -Q "select 1" && grep -q "MSSQL CONFIG COMPLETE" ./config.log
