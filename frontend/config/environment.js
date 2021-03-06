/* jshint node: true */

module.exports = function(environment) {
  var ENV = {
   modulePrefix: 'd-flow-ember',
   environment: environment,
   rootURL: '/index',
   locationType: 'hash',
   EmberENV: {
     FEATURES: {
       // Here you can enable experimental features on an ember canary build
       // e.g. 'with-controller': true
     }
   },

   i18n: {
    defaultLocale: 'sv'
   },

   APP: {
     authenticationBaseURL: '/session',
     serviceURL:''
     // Here you can pass flags/options to your application instance
     // when it is created
   }
  };

  if (environment === 'development') {
    // ENV.APP.LOG_RESOLVER = true;
    ENV.APP.LOG_ACTIVE_GENERATION = true;
    ENV.APP.LOG_TRANSITIONS = true;
    ENV.APP.LOG_TRANSITIONS_INTERNAL = true;
    //ENV.APP.LOG_VIEW_LOOKUPS = true;
    ENV.contentSecurityPolicyHeader = 'Disabled-Content-Security-Policy';
    //ENV.APP.authenticationBaseURL = 'http://localhost:3000/session';
    //ENV.APP.serviceURL = 'http://localhost:3000';
  }

  if (environment === 'test') {
    // Testem prefers this...
    ENV.locationType = 'none';

    // keep test console output quieter
    ENV.APP.LOG_ACTIVE_GENERATION = false;
    ENV.APP.LOG_VIEW_LOOKUPS = false;

    ENV.APP.rootElement = '#ember-testing';
  }


  return ENV;
};
