FROM perl:5.20
RUN cpanm install Carp && \
  cpanm install Email::MIME && \
  cpanm install File::Basename && \
  cpanm install Net::POP3 && \
  cpanm install Data::Dumper && \
  cpanm install Redis && \
  cpanm install JSON && \
  cpanm IO::Socket::SSL
COPY app.pl /usr/src/app/app.pl
COPY start.sh /usr/src/app/start.sh
WORKDIR /usr/src/app
RUN chmod 755 start.sh
CMD ["sh", "/usr/src/app/start.sh" ]