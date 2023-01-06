#!/bin/bash

if ! command -v docker &> /dev/null
then
    echo "Docker not found! Required Docker 20 or greater"
    exit
fi

DOCKER_VERSION=$(docker version -f "{{.Server.Version}}")
DOCKER_VERSION_MAJOR=$(echo "$DOCKER_VERSION"| cut -d'.' -f 1)

if [ ! "${DOCKER_VERSION_MAJOR}" -ge 20 ] ; then
    echo "Invalid Docker version! Required Docker 20 or greater"
    exit
fi

NAME=
DOMAIN=test
IP=172.17.0.2
IMAGE=imdt/bigbluebutton:2.6.x-develop
GITHUB_USER=
CERT_DIR=
REMOVE_CONTAINER=0
CONTAINER_IMAGE=

for var in "$@"
do
    if [[ ! $var == *"--"* ]] && [ ! $NAME ]; then
        NAME="$var"
    elif [[ $var == --image* ]] ; then
        IMAGE=${var#*=}
        CONTAINER_IMAGE=$IMAGE
    elif [[ $var == "--remove" ]] ; then
        REMOVE_CONTAINER=1
    fi
done

echo "Container name: $NAME"

if [ ! $NAME ] ; then
    echo "Missing name: ./create_bbb.sh [--update] [--fork=github_user] [--domain=domain_name] [--ip=ip_address] [--image=docker_image] [--cert=certificate_dir] {name}"
    exit 1
fi


for container_id in $(docker ps -f name=$NAME -q) ; do 
    echo "Killing current $NAME"
    docker kill $container_id;
done

for container_id in $(docker ps -f name=$NAME -q -a); do
    CONTAINER_IMAGE="$(docker inspect --format '{{ .Config.Image }}' $NAME)"
    echo "Removing container $NAME" 
    docker rm $container_id;
done

if [ "$(docker volume ls | grep \docker_in_docker${NAME}$)" ]; then
    echo "Removing volume docker_in_docker$NAME"
    sudo docker volume rm docker_in_docker$NAME;
fi

# Remove entries from ~/.ssh/config
if [ -f ~/.ssh/config ] ; then
  sed -i '/^Host '"$NAME"'$/,/^$/d' ~/.ssh/config
  sed -i '/^Host '"$NAME-with-ports"'$/,/^$/d' ~/.ssh/config
fi

if [ $REMOVE_CONTAINER == 1 ]; then
  if [ $CONTAINER_IMAGE ]; then
    echo
    echo "----"
    read -p "Do you want to remove the image $CONTAINER_IMAGE (y/n)? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]];  then
      docker image rm $CONTAINER_IMAGE --force
      echo "Image $CONTAINER_IMAGE removed!"
    fi
  fi

  if [ -d $HOME/$NAME ] ; then
    echo
    echo "----"
    read -p "Do you want to remove all files from $HOME/$NAME (y/n)? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]];  then
      rm -rf $HOME/$NAME
    fi
  fi

  echo "Container $NAME removed!"
  exit 0
fi


echo "Using image $IMAGE"

for var in "$@"
do
    if [ $var == "--update" ] ; then
        echo "Checking for new version of image $IMAGE"
        docker image tag $IMAGE ${IMAGE}_previous
        docker image rm $IMAGE
        docker pull $IMAGE
        docker rmi ${IMAGE}_previous
    elif [[ $var == --ip* ]] ; then
        IP=${var#*=}
        if [[ $IP == 172.17.* ]] ; then
            echo "IP address can't start with 172.17"
            return 1 2>/dev/null
            exit 1
        else
            echo "Setting IP to $IP"
        fi
    elif [[ $var == --fork* ]] ; then
        GITHUB_USER=${var#*=}
    elif [[ $var == --cert* ]] ; then
        CERT_DIR=${var#*=}
    elif [[ $var == --domain* ]] ; then
        DOMAIN=${var#*=}
    fi
done

mkdir -p $HOME/$NAME/
HOSTNAME=$NAME.$DOMAIN


BBB_SRC_FOLDER=$HOME/$NAME/bigbluebutton
if [ -d $BBB_SRC_FOLDER ] ; then
        echo "Directory $HOME/$NAME/bigbluebutton already exists, not initializing."
        sleep 2;
else
        cd $HOME/$NAME/

        if [ $GITHUB_USER ] ; then
            git clone git@github.com:$GITHUB_USER/bigbluebutton.git
            
            echo "Adding Git Upstream to https://github.com/bigbluebutton/bigbluebutton.git"
            cd $HOME/$NAME/bigbluebutton
            git remote add upstream https://github.com/bigbluebutton/bigbluebutton.git
        else
            git clone https://github.com/bigbluebutton/bigbluebutton.git
        fi
fi

cd

#Shared folder to exchange data between local machine and container
BBB_SHARED_FOLDER=$HOME/$NAME/shared
mkdir -p $BBB_SHARED_FOLDER

###Certificate start -->
mkdir $HOME/$NAME/certs/ -p
if [ $CERT_DIR ] ; then
    echo "Certificate directory passed: $CERT_DIR"
    if [ ! -f $CERT_DIR/fullchain.pem ] ; then
        echo "Error! $CERT_DIR/fullchain.pem not found."
        exit 0
    elif [ ! -f $CERT_DIR/privkey.pem ] ; then
        echo "Error! $CERT_DIR/privkey.pem not found."
        exit 0
    fi

    cp $CERT_DIR/fullchain.pem $HOME/$NAME/certs/fullchain.pem
    cp $CERT_DIR/privkey.pem $HOME/$NAME/certs/privkey.pem
    echo "Using provided certificate successfully!"
elif [ -f $HOME/$NAME/certs/fullchain.pem ] && [ -f $HOME/$NAME/certs/privkey.pem ] ; then
    echo "Certificate already exists, not creating."
    sleep 2;
else
    mkdir $HOME/$NAME/certs-source/ -p
    #Create root CA
    cd $HOME/$NAME/certs-source/
    openssl rand -base64 48 > bbb-dev-ca.pass ;
    chmod 600 bbb-dev-ca.pass ;
    openssl genrsa -des3 -out bbb-dev-ca.key -passout file:bbb-dev-ca.pass 2048 ;

    openssl req -x509 -new -nodes -key bbb-dev-ca.key -sha256 -days 1460 -passin file:bbb-dev-ca.pass -out bbb-dev-ca.crt -subj "/C=CA/ST=BBB/L=BBB/O=BBB/OU=BBB/CN=BBB-DEV" ;

    #Copy the CA to your trusted certificates ( so your browser will accept this certificate )
    sudo mkdir /usr/local/share/ca-certificates/bbb-dev/
    sudo cp $HOME/$NAME/certs-source/bbb-dev-ca.crt /usr/local/share/ca-certificates/bbb-dev/
    sudo chmod 644 /usr/local/share/ca-certificates/bbb-dev/bbb-dev-ca.crt
    sudo update-ca-certificates

    #Generate a certificate for your first local BBB server
    cd $HOME/$NAME/certs-source/
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

    cd $HOME/$NAME/
    cp $HOME/$NAME/certs-source/bbb-dev-ca.crt certs/
    cat $HOME/$NAME/certs-source/$HOSTNAME.crt > certs/fullchain.pem
    cat $HOME/$NAME/certs-source/bbb-dev-ca.crt >> certs/fullchain.pem
    cat $HOME/$NAME/certs-source/$HOSTNAME.key > certs/privkey.pem
    rm -r $HOME/$NAME/certs-source
    echo "Self-signed certificate created successfully!"
fi
### <-- Certificate end


SUBNET="$(echo $IP |cut -d "." -f 1).$(echo $IP |cut -d "." -f 2).0.0"

if [ $SUBNET == "172.17.0.0" ] ; then
    SUBNETNAME="bridge"
else
    SUBNETNAME="bbb_network_$(echo $IP |cut -d "." -f 1)_$(echo $IP |cut -d "." -f 2)"
fi

if [ ! "$(docker network ls | grep $SUBNETNAME)" ]; then
  echo "Creating $SUBNETNAME network ..."
  docker network create --driver=bridge --subnet=$SUBNET/16 $SUBNETNAME
else
  echo "$SUBNETNAME network exists."
fi


NETWORKPARAMS=""
if [ $SUBNETNAME != "bridge" ] ; then
    NETWORKPARAMS="--ip=$IP --network $SUBNETNAME"
fi


#Create sbt publish folders to map in Docker
#It will sync the sbt libs in host machine and docker container (useful for backend development)
mkdir -p $HOME/.m2/repository/org/bigbluebutton
mkdir -p $HOME/.ivy2/local/org.bigbluebutton

docker run -d --name=$NAME --hostname=$HOSTNAME $NETWORKPARAMS -env="container=docker" --env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" --env="DEBIAN_FRONTEND=noninteractive" -v "/var/run/docker.sock:/var/run/docker.sock:rw" --cap-add="NET_ADMIN" --privileged -v "$HOME/$NAME/certs/:/local/certs:rw" --cgroupns=host -v "$BBB_SRC_FOLDER:/home/bigbluebutton/src:rw" -v "$BBB_SHARED_FOLDER:/home/bigbluebutton/shared:rw" -v "$HOME/.m2/repository/org/bigbluebutton:/home/bigbluebutton/.m2/repository/org/bigbluebutton:rw" -v "$HOME/.ivy2/local/org.bigbluebutton:/home/bigbluebutton/.ivy2/local/org.bigbluebutton:rw" -v docker_in_docker$NAME:/var/lib/docker -t $IMAGE

mkdir $HOME/.bbb/ &> /dev/null
echo "docker exec -u bigbluebutton -w /home/bigbluebutton/ -it $NAME /bin/bash  -l" > $HOME/.bbb/$NAME.sh
chmod 755 $HOME/.bbb/$NAME.sh

#Create ssh key if absent
if [ ! -e ~/.ssh/id_rsa.pub ]; then
    yes '' | ssh-keygen -N ''
fi


docker exec -u bigbluebutton $NAME bash -c "mkdir -p ~/.ssh && echo $(cat ~/.ssh/id_rsa.pub) >> ~/.ssh/authorized_keys"

sleep 5s
if [ $SUBNETNAME == "bridge" ] ; then
    DOCKERIP="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $NAME)"
else
    DOCKERIP="$(docker inspect --format '{{ .NetworkSettings.Networks.'"$SUBNETNAME"'.IPAddress }}' $NAME)"
fi

if [ ! $DOCKERIP ] ; then
    echo "ERROR! Trying to discover Docker IP"
    exit 0
fi

sudo sed -i "/$HOSTNAME/d" /etc/hosts
echo $DOCKERIP $HOSTNAME | sudo tee -a /etc/hosts

ssh-keygen -R "$HOSTNAME"
ssh-keygen -R "$DOCKERIP"
# ssh-keygen -R [hostname],[ip_address]

ssh-keyscan -H "$DOCKERIP" >> ~/.ssh/known_hosts
ssh-keyscan -H "$HOSTNAME" >> ~/.ssh/known_hosts
# ssh-keyscan -H [hostname],[ip_address] >> ~/.ssh/known_hosts

if [ ! -z "$(tail -1 ~/.ssh/config)" ] ; then
  echo "" >> ~/.ssh/config
fi

if ! grep -q "\Host ${NAME}$" ~/.ssh/config ; then
  echo "Adding alias $NAME to ~/.ssh/config"
	echo "Host $NAME
    HostName $HOSTNAME
    User bigbluebutton
    Port 22
" >> ~/.ssh/config
fi

if ! grep -q "\Host ${NAME}-with-ports$" ~/.ssh/config ; then
    echo "Adding alias $NAME-with-ports to ~/.ssh/config"
    echo "Host $NAME-with-ports
    HostName $HOSTNAME
    User bigbluebutton
    Port 22
    LocalForward 6379 localhost:6379
    LocalForward 4101 localhost:4101
" >> ~/.ssh/config
fi

#Set Zsh as default and copy local bindkeys
if [ -d ~/.oh-my-zsh ]; then
    echo "Found oh-my-zsh installed. Setting as default in Docker as well."
    docker exec -u bigbluebutton $NAME bash -c "sudo chsh -s /bin/zsh bigbluebutton"
    grep "^bindkey" ~/.zshrc | xargs -I{} docker exec -u bigbluebutton $NAME bash -c "echo {} >> /home/bigbluebutton/.zshrc"
fi


echo "------------------"
echo "Docker infos"
echo "IP $DOCKERIP"
echo "Default user: bigbluebutton"
echo "Default passwork: bigbluebutton"
echo "" 
echo ""
docker exec -u bigbluebutton $NAME bash -c "bbb-conf --salt"
echo ""
echo ""
echo "------------------"
tput setaf 2; echo "Container created successfully!"; tput sgr0
echo ""
tput setaf 3; echo "BBB URL: https://$HOSTNAME"; tput sgr0
tput setaf 3; echo "Access Docker using: ssh $NAME"; tput sgr0
echo ""
echo "------------------"
echo ""
echo ""
tput setaf 4; echo "or to run Akka/Mongo locally use: ssh $NAME-with-ports"; tput sgr0
echo ""
echo ""
