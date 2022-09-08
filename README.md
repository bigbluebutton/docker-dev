# docker-dev

How to use Docker to setup a development environment for BigBlueButton

## Environment

We're considering you are using a [Ubuntu 20.04 LTS](https://ubuntu.com/download/desktop) but other versions/distributions can work too.

An internet connection is required. It can be a shared network ( no need to forward ports in your router ).

## SSL certificate

Running a BigBlueButton server requires a SSL certificate. The install script will automatically generate an self-signed certificate or you can rather specify a folder which contains a previous generated certificate.


## Docker setup

The next script depends on having docker available to your user, so before proceeding, run the following command (note that a computer reboot is required):

```sh
sudo usermod -aG docker `whoami`
sudo reboot
```

## Container setup

1. Save (right click, save as) the creation script in home directory (`~`): [create_bbb.sh](create_bbb.sh?raw=1)

2. Add permissions to the script:
```sh
chmod +x create_bbb.sh
```

3. Run the script ( it will remove previously created dockers and create a new one):
Docker **bbb 2.6**
```
./create_bbb.sh bbb26 --image=imdt/bigbluebutton:2.6.x-develop --update
```
Docker **bbb 2.5**
```
./create_bbb.sh bbb25 --image=imdt/bigbluebutton:2.5.x-develop --update
```
Docker **bbb 2.4**
```
./create_bbb.sh bbb24 --image=imdt/bigbluebutton:2.4.x-develop --update
```


Parameters:
`./create_bbb.sh [--update] [--fork=github_user] [--domain=domain_name] [--ip=ip_address] [--image=docker_image] [--cert=certificate_dir] {name}`
- {name}: Name of the container (e.g `bbb26`) **(REQUIRED)**
- --update: check for new image version `--update`
- --domain: set the host domain (e.g `--domain=test`), default: `test`. BBB URL will be `https://{NAME} + {DOMAIN}`
- --cert: specify the directory which contains a certificate (`fullchain.pem` and `privkey.pem`) (e.g `--cert=/tmp`) *(if absent a new certificate will be created)*
- --ip: force container IP (e.g `--ip=172.17.0.2`)
- --fork: Username in Github with bbb Fork `--fork=bigbluebutton`
- --image: Force an image different than default `--image=imdt/bigbluebutton:2.6.x-develop`
## Using the container

## SSH session within the container
``` 
ssh bbb26
``` 
Replace **bbb26** with the {name} param of `create_bbb.sh`


That's all, open https://bbb26.test in your browser and enjoy.

PS: if you see certificate error in your browser, you need to add the CA certificate in it's trusted certificates. Instructions for Chrome and Firefox can be found [here](https://github.com/bigbluebutton/docker-dev/issues/1)

---
## BBB-Conf
Link to the API-Mate: `bbb-conf --salt`

Restart BBB: `sudo bbb-conf --restart`

Check configs: `sudo bbb-conf --check`

---
## Troubleshooting

In case of problems, you can update the packages by running:

```sh
sudo apt update
sudo apt dist-upgrade -y
```

---
# Instructions to run BigBlueButton from source (via command-line)
- **HTML5 - bigbluebutton-html5**: the Front-End (users meeting interface) [*Meteor*]
- **AKKA - akka-bbb-apps**: Backend that exchange msgs with Frontend through Redis pub/sub msgs (stores the meeting state and execute validations for Html5, *e.g: Can John send a message?*) [*Scala*]
- **API - bigbluebutton-web**: Receives requests e.g: Create room, Enter room (when someone asks to enter the room, enters the API and then is redirected to html5) [*Grails*]
    - **-bbb-common-web**: Contains useful functions that are used by the API [*JAVA*]
- **bbb-common-message**: Contains all Redis messages! Akka and the API import this project to know the existing messages [*JAVA*]

Further informations in https://docs.bigbluebutton.org/2.6/dev.html

---
## HTML5 client

#### Running HTML5
```
cd ~/src/bigbluebutton-html5/
./run-dev.sh
```

#### Running HTML5 with **Full RESET** (needed sometimes)
```
cd ~/src/bigbluebutton-html5/
./run-dev.sh --reset
```

---
## Common-Message (required for BBB-Web and Akka)
```
cd ~/src/bbb-common-message
./deploy.sh
``` 

---
## BBB-Web (API)

#### Running Bigbluebutton-web
```
cd ~/src/bigbluebutton-web/
./run-dev.sh
```

**If `bbb-common-web` was changed run:**
```
cd ~/src/bbb-common-web
./deploy.sh
cd ~/src/bigbluebutton-web/
./build.sh
```


---
## Akka-apps

#### Running Akka within **bbb-docker-dev**
```bash
cd ~/src/akka-bbb-apps/
./run-dev.sh
```

#### Running Akka on **IntelliJ IDEA**
- [Requires Common-Message](#common-message-required-for-bbb-web-and-akka)
- Open bbb-docker-dev SSH connection appending `-with-ports` to the command *(it will create tunnel for Redis port 6379)*
```bash
ssh {container_name}-with-ports
```
- Run Akka within Docker once, to set the configs
```bash
cd ~/src/akka-bbb-apps/
./run-dev.sh
```
- If everything is working, press `Ctrl + C` to stop

- Open IDEA, open the Sbt tab and run:
```
~reStart
```
![image](https://user-images.githubusercontent.com/5660191/158892260-8356d117-3be8-424a-aa24-ca405511f4e5.png)


---
## Redis
- To track the exchange of messages between applications 
```
redis-cli psubscribe "*" | grep --line-buffered -v 'pmessage\|CheckRunningAndRecording\|MeetingInfoAnalyticsServiceMsg\|CheckAliveP\|GetUsersStatusToVoiceConfSysMsg\|SendCursorPosition\|DoLatencyTracerMsg'
```
