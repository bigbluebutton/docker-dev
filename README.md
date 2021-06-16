# docker-dev

How to use Docker to setup a development environment for BigBlueButton

## Environment

We're considering you are using a [Ubuntu 20.04 LTS](https://ubuntu.com/download/desktop) but other versions/distributions can work too.

An internet connection is required. It can be a shared network ( no need to forward ports in your router ).

## SSL certificate

Running a BigBlueButton server requires a SSL certificate. For this setup we're going to configure our own CA and emit our own certificate.

### Create root CA

The following commands will create a root certificate authority with a random private key passphrase.

```sh
mkdir ~/bbb-docker-dev-setup/
cd ~/bbb-docker-dev-setup/

openssl rand -base64 48 > bbb-dev-ca.pass ;
chmod 600 bbb-dev-ca.pass ;
openssl genrsa -des3 -out bbb-dev-ca.key -passout file:bbb-dev-ca.pass 2048 ;

openssl req -x509 -new -nodes -key bbb-dev-ca.key -sha256 -days 1460 -passin file:bbb-dev-ca.pass -out bbb-dev-ca.crt -subj "/C=CA/ST=BBB/L=BBB/O=BBB/OU=BBB/CN=BBB-DEV" ;
```

Copy the CA to your trusted certificates ( so your browser will accept this certificate ):

```sh
sudo mkdir /usr/local/share/ca-certificates/bbb-dev/
sudo cp ~/bbb-docker-dev-setup/bbb-dev-ca.crt /usr/local/share/ca-certificates/bbb-dev/
sudo chmod 644 /usr/local/share/ca-certificates/bbb-dev/bbb-dev-ca.crt
sudo update-ca-certificates
```

### Generate a certificate for your first local BBB server

Here we're going to generate a certificate for domain `bbb-dev-01.test`.

```sh
cd ~/bbb-docker-dev-setup/
# change here if you want a different name
NAME="bbb-dev-01"
HOSTNAME="${NAME}.test"
openssl genrsa -out ${HOSTNAME}.key 2048
rm ${HOSTNAME}.csr ${HOSTNAME}.crt ${HOSTNAME}.key
cat > ${HOSTNAME}.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${HOSTNAME}
EOF

openssl req -nodes -newkey rsa:2048 -keyout ${HOSTNAME}.key -out ${HOSTNAME}.csr -subj "/C=CA/ST=BBB/L=BBB/O=BBB/OU=BBB/CN=${HOSTNAME}" -addext "subjectAltName = DNS:${HOSTNAME}" 

openssl x509 -req -in ${HOSTNAME}.csr -CA bbb-dev-ca.crt -CAkey bbb-dev-ca.key -CAcreateserial -out ${HOSTNAME}.crt -days 825 -sha256 -passin file:bbb-dev-ca.pass -extfile ${HOSTNAME}.ext
cd
```

## Container setup

This docker image is running a single container with BBB packages built from `develop` branch.

Create a script in your home directory named `create_bbb.sh` with the following content:

```sh
#!/bin/bash
NAME="bbb-dev-01"  # change here if you want a different name
HOSTNAME="${NAME}.test"
IMAGE=imdt/bigbluebutton:2.3.x-develop

# retag the commit to force a lookup but keep in cache
docker image inspect $IMAGE &>/dev/null && ( docker image tag $IMAGE $IMAGE-previous ; docker image rm $IMAGE )

# kill/remove existing container
docker inspect $NAME &> /dev/null && (
    echo "Container with name $NAME already exists, removing."
    docker kill $NAME ;
    docker rm $NAME ;
)

if [ -d $HOME/$NAME ] ; then
        echo "Directory $HOME/$NAME already exists, not initializing."
        sleep 2;
else
        mkdir $HOME/$NAME/
        cd $HOME/$NAME/
        git clone https://github.com/bigbluebutton/bigbluebutton.git
fi

cd $HOME/$NAME/
mkdir $HOME/$NAME/certs/ -p
cp ~/bbb-docker-dev-setup/bbb-dev-ca.crt certs/
cat ~/bbb-docker-dev-setup/$HOSTNAME.crt > certs/fullchain.pem
cat ~/bbb-docker-dev-setup/bbb-dev-ca.crt >> certs/fullchain.pem
cat ~/bbb-docker-dev-setup/$HOSTNAME.key > certs/privkey.pem

cd
BBB_SRC_FOLDER=$HOME/$NAME/bigbluebutton

docker run -d --name=$NAME --hostname=$HOSTNAME --env="NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/bbb-dev/bbb-dev-ca.crt" --env="container=docker" --env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" --env="DEBIAN_FRONTEND=noninteractive" --volume="/var/run/docker.sock:/var/run/docker.sock:rw" --cap-add="NET_ADMIN" --privileged --volume="$HOME/$NAME/certs/:/local/certs:rw" --volume="/sys/fs/cgroup:/sys/fs/cgroup:ro" --volume="$BBB_SRC_FOLDER:/home/bigbluebutton/src:rw" --volume=docker_in_docker$NAME:/var/lib/docker -t $IMAGE

mkdir $HOME/.bbb/ &> /dev/null
echo "docker exec -u bigbluebutton -w /home/bigbluebutton/ -it $NAME /bin/bash  -l" > $HOME/.bbb/$NAME.sh
chmod 755 $HOME/.bbb/$NAME.sh

echo "docker exec -u bigbluebutton -w /home/bigbluebutton/ $NAME /bin/hostname --ip-address" > $HOME/.bbb/ip-$NAME.sh
chmod 755 $HOME/.bbb/ip-$NAME.sh
```

Add permissions to the script:

```sh
chmod 755 create_bbb.sh
```

Run the script ( it will remove previously created dockers and create a new one):

```sh
 ./create_bbb.sh
```

## Shell session within the container

You can open a shell session with the following command:

```sh
./.bbb/bbb-dev-01.sh
```

## Configure your local machine DNS

Your computer `/etc/hosts` file must be configured in order to resolve the name of your container. You can do it by running the following command:

```sh
echo `./.bbb/ip-bbb-dev-01.sh | xargs -n 1 echo -n`" bbb-dev-01.test." | sudo tee /etc/hosts
```

## Running HTML5 from source code

To execute HTML5 component from source code, you need to open a shell session within your container ( see previous section ) and execute:

```sh
# Restart all BBB services
sudo bbb-conf --restart

## Stop MongoDB and bbb-html5 services that are running from packages
sudo systemctl stop bbb-html5 mongod

## Start meteor in development mode ( it starts a bundled mongo too )
cd ~/src/bigbluebutton-html5/
npm install
npm start
```

That's all, open https://bbb-dev-01.test in your browser and enjoy.
