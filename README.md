# SYNOPSIS

This container will connect to POP email address and insert Yourporter enquiries
into a redis Q. for further processing.

# make sure you have redis running on local network

  docker network create local
  docker run -d --name redis --restart always --network=local redis

# clone & build image

  git clone git@github.com:jhiver/yourporter-email-enquiry-fetch.git
  cd yourporter-email-enquiry-fetch
  docker build -t yourporter-email-enquiry-fetch .

# run service

  docker run ---name yourporter-email-enquiry-fetch -it --rm --network=local yourporter-email-enquiry-fetch