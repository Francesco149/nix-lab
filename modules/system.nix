{ config, ... }:
{
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";

  security.acme = {
    acceptTerms = true;
    defaults.email = config.lab.certs.email;
  };
}
