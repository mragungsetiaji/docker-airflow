FROM balenalib/amd64-ubuntu:bionic-build
LABEL name="mragungsetiaji/airflow"
LABEL version="4"

# BASE IMAGE : ubuntu1804/python370-amd64
# =======================================================================================================
# remove several traces of debian python
RUN apt-get purge -y python.*

# http://bugs.python.org/issue19846
ENV LANG C.UTF-8

# key 63C7CC90: public key "Simon McVittie <smcv@pseudorandom.co.uk>" imported
# key 3372DCFA: public key "Donald Stufft (dstufft) <donald@stufft.io>" imported
RUN gpg --keyserver keyring.debian.org --recv-keys 4DE8FF2A63C7CC90 \
	&& gpg --keyserver keyserver.ubuntu.com --recv-key 6E3CBCE93372DCFA \
	&& gpg --keyserver keyserver.ubuntu.com --recv-keys 0x52a43a1e4b77b059

ENV PYTHON_VERSION 3.7.0

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 10.0.1

ENV SETUPTOOLS_VERSION 39.1.0

RUN set -x \
	&& curl -SLO "http://resin-packages.s3.amazonaws.com/python/v$PYTHON_VERSION/Python-$PYTHON_VERSION.linux-amd64.tar.gz" \
	&& echo "d3fd6235e2a17036334770f4c668206e398fb4b7e7009fb764cfb4abb78c13c2  Python-$PYTHON_VERSION.linux-amd64.tar.gz" | sha256sum -c - \
	&& tar -xzf "Python-$PYTHON_VERSION.linux-amd64.tar.gz" --strip-components=1 \
	&& rm -rf "Python-$PYTHON_VERSION.linux-amd64.tar.gz" \
	&& ldconfig \
	&& if [ ! -e /usr/local/bin/pip3 ]; then : \
		&& curl -SLO "https://raw.githubusercontent.com/pypa/get-pip/430ba37776ae2ad89f794c7a43b90dc23bac334c/get-pip.py" \
		&& echo "19dae841a150c86e2a09d475b5eb0602861f2a5b7761ec268049a662dbd2bd0c  get-pip.py" | sha256sum -c - \
		&& python3 get-pip.py \
		&& rm get-pip.py \
	; fi \
	&& pip3 install --no-cache-dir --upgrade --force-reinstall pip=="$PYTHON_PIP_VERSION" setuptools=="$SETUPTOOLS_VERSION" \
	&& find /usr/local \
		\( -type d -a -name test -o -name tests \) \
		-o \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
		-exec rm -rf '{}' + \
	&& cd / \
	&& rm -rf /usr/src/python ~/.cache

# install "virtualenv", since the vast majority of users of this image will want it
RUN pip3 install --no-cache-dir virtualenv

ENV PYTHON_DBUS_VERSION 1.2.4

# install dbus-python dependencies 
RUN apt-get update && apt-get install -y --no-install-recommends \
		libdbus-1-dev \
		libdbus-glib-1-dev \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get -y autoremove

# install dbus-python
RUN set -x \
	&& mkdir -p /usr/src/dbus-python \
	&& curl -SL "http://dbus.freedesktop.org/releases/dbus-python/dbus-python-$PYTHON_DBUS_VERSION.tar.gz" -o dbus-python.tar.gz \
	&& curl -SL "http://dbus.freedesktop.org/releases/dbus-python/dbus-python-$PYTHON_DBUS_VERSION.tar.gz.asc" -o dbus-python.tar.gz.asc \
	&& gpg --verify dbus-python.tar.gz.asc \
	&& tar -xzC /usr/src/dbus-python --strip-components=1 -f dbus-python.tar.gz \
	&& rm dbus-python.tar.gz* \
	&& cd /usr/src/dbus-python \
	&& PYTHON=python$(expr match "$PYTHON_VERSION" '\([0-9]*\.[0-9]*\)') ./configure \
	&& make -j$(nproc) \
	&& make install -j$(nproc) \
	&& cd / \
	&& rm -rf /usr/src/dbus-python

# make some useful symlinks that are expected to exist
RUN cd /usr/local/bin \
	&& ln -sf pip3 pip \
	&& { [ -e easy_install ] || ln -s easy_install-* easy_install; } \
	&& ln -sf idle3 idle \
	&& ln -sf pydoc3 pydoc \
	&& ln -sf python3 python \
	&& ln -sf python3-config python-config

# set PYTHONPATH to point to dist-packages
ENV PYTHONPATH /usr/lib/python3/dist-packages:$PYTHONPATH

# Airflow
# ======================================================================================================

# Airflow env
ENV AIRFLOW_USER=airflow
ENV AIRFLOW_HOME=/usr/local/airflow
ENV AIRFLOW_DB_USER=airflow
ENV AIRFLOW_GPL_UNIDECODE=yes

RUN mkdir -p ${AIRFLOW_HOME}
WORKDIR ${AIRFLOW_HOME}
RUN useradd -ms /bin/bash -d ${AIRFLOW_HOME} -G sudo ${AIRFLOW_USER} 
RUN apt-get install -y --fix-broken 
RUN apt-get autoremove
RUN apt-get update 
RUN apt-get -y upgrade
RUN apt-get install -y --no-install-recommends apt-utils \
    mysql-client  \
    libmysqlclient-dev \
    libssl-dev \
    libffi-dev

# apt-get and system utilities
RUN apt-get update && apt-get install -y \
    apt-utils apt-transport-https debconf-utils gcc build-essential g++-5 \
    && rm -rf /var/lib/apt/lists/*

# Install Connection pyodbc to SQLServer
# driver='{ODBC Driver 17 for SQL Server}'
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
RUN apt-get update && ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev
RUN apt-get update && ACCEPT_EULA=Y apt-get install -y mssql-tools
RUN echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
RUN /bin/bash -c "source ~/.bashrc"

# install necessary locales
RUN apt-get update && apt-get install -y locales \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen

# install SQL Server Python SQL Server connector module - pyodbc
RUN pip install pyodbc

# Install Airflow
COPY requirements.txt ${AIRFLOW_HOME}
RUN pip install --no-cache-dir -r requirements.txt

# Add tools airflow dependencies
ADD ./tools ${AIRFLOW_HOME}
COPY ./tools/docker/script/entrypoint.sh /entrypoint.sh
RUN chown -R ${AIRFLOW_USER}.${AIRFLOW_USER} ${AIRFLOW_HOME}
USER ${AIRFLOW_USER}

# Run application
EXPOSE 8080 5555 8793

USER ${AIRFLOW_USER}
WORKDIR ${AIRFLOW_HOME}
ENTRYPOINT ["/entrypoint.sh"]

