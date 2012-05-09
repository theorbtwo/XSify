package ExtUtils::XSify::Constructor;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::FunctionDecl';

has 'access', is => 'ro';

'new';
