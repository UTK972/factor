USING: help.markup help.syntax assocs strings logging
logging.analysis smtp ;
IN: logging.insomniac

HELP: insomniac-smtp-host
{ $var-description "An SMTP server to use for e-mailing log reports. If not set, the value of " { $link smtp-host } " is used." } ;

HELP: insomniac-smtp-port
{ $var-description "An SMTP server port to use for e-mailing log reports. If not set, the value of " { $link smtp-port } " is used." } ;

HELP: insomniac-sender
{ $var-description "The originating e-mail address for mailing log reports. Must be set before " { $vocab-link "logging.insomniac" } " is used." } ;

HELP: insomniac-recipients
{ $var-description "A sequence of e-mail addresses to mail log reports to. Must be set before " { $vocab-link "logging.insomniac" } " is used." } ;

HELP: ?analyze-log
{ $values { "service" "a log service name" } { "word-names" "a sequence of strings" } { "string" string } }
{ $description "Analyzes the most recent log and outputs the string analysis, or outputs " { $link f } " if it doesn't exist." }
{ $see-also analyze-log } ;

HELP: email-log-report
{ $values { "service" "a log service name" } { "word-names" "a sequence of strings" } }
{ $description "E-mails a log report for the given log service. The " { $link insomniac-smtp-host } ", " { $link insomniac-sender } " and " { $link insomniac-recipients } " parameters must be set up first. The " { $snippet "word-names" } " parameter is documented in " { $link analyze-entries } "." } ;

HELP: schedule-insomniac
{ $values { "alist" "a sequence of pairs of shape " { $snippet "{ service word-names }" } } }
{ $description "Starts a thread which e-mails log reports and rotates logs daily." } ;

ARTICLE: "logging.insomniac" "Automating log analysis and rotation"
"The " { $vocab-link "logging.insomniac" } " vocabulary builds on the " { $vocab-link "logging.analysis" } " vocabulary. It provides support for e-mailing log reports and rotating logs on a daily basis. E-mails are sent using the " { $vocab-link "smtp" } " vocabulary."
$nl
"Required configuration parameters:"
{ $subsection insomniac-sender }
{ $subsection insomniac-recipients }
"Optional configuration parameters:"
{ $subsection insomniac-smtp-host }
{ $subsection insomniac-smtp-port }
"E-mailing a one-off report:"
{ $subsection email-log-report }
"E-mailing reports and rotating logs on a daily basis:"
{ $subsection schedule-insomniac } ;

ABOUT: "logging.insomniac"