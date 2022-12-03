:tocdepth: 1

Abstract
========

SQuaRE has standardized on Python with the FastAPI_ framework for writing web applications, and suggests a basic application structure via the `FastAPI Safir App`_ project template.
These tools provide a solid starting foundation but leave numerous architectural decisions unresolved.
This tech note collects design patterns and architectural approaches used by the author when constructing FastAPI applications, which may be of interest as a model (or cautionary tale) for others.

.. _FastAPI: https://fastapi.tiangolo.com/
.. _FastAPI Safir App: https://github.com/lsst/templates/tree/main/project_templates/fastapi_safir_app

Nothing described here is a project standard or requirement.
It is only the personal opinion of the author.

This approach has been used, in various iterations and with varying degrees of faithfulness, to design Gafaelfawr_, crawlspace_, datalinker_, mobu_, and vo-cutouts_.
Readers are encouraged to examine those applications and draw their own conclusions about the results.

.. _Gafaelfawr: https://github.com/lsst-sqre/gafaelfawr
.. _crawlspace: https://github.com/lsst-sqre/crawlspace
.. _datalinker: https://github.com/lsst-sqre/datalinker
.. _mobu: https://github.com/lsst-sqre/mobu
.. _vo-cutouts: https://github.com/lsst-sqre/vo-cutouts

Python version
==============

Unless there is a specific hard requirement, do not support Python versions older than Python 3.10.

In general, FastAPI web applications should update to the current release of Python shortly after it is released and do not need to support more than one version of Python except during that transition period.
I update to a newer version of Python once it becomes the default in Debian unstable.

All supported versions should be tested with GitHub Actions.
Don't forget to update GitHub Actions configuration when changing the supported version.

.. _architecture:

High-level architecture
=======================

The architecture described here is inspired by `hexagonal architecture`_, sometimes also known as "ports and adapters," although it does not strictly follow that design pattern.
It borrows the layering design and dependency structure, but creates interfaces only lazily once there are two implementations, rather than proactively as an architectural aid.
This architecture also makes extensive use of data objects (objects that are only containers for data with no or minimal behavior attached) to pass structured information between the layers of the architecture.

.. _hexagonal architecture: https://fideloper.com/hexagonal-architecture

Here is the high-level architecture in diagram form.
In this diagram, an incoming request from a user flows from top to bottom, and the response flows from bottom to top.

.. figure:: /_static/architecture.svg
   :name: Architecture overview

Not shown in the diagram is that most communication between the handler, service, and storage layers (the heart of the application) is done using *models*, which is the term we use for data objects.

The components in this model are:

config
    The external configuration of the application.
    Since all of our applications target Kubernetes, the ultimate source of this configuration is generally ``ConfigMap`` or ``Secret`` resources constructed via Helm charts.
    This configuration may be injected via a configuration file or environment variables.
    Inside the application, it is parsed and stored in a model.

dependencies
    FastAPI dependencies (and, occasionally, middleware, although dependencies are preferred over middleware where possible) manage resources that are shared across multiple requests.
    For example, external database connections, Redis connections, and memory caches should all be implemented as FastAPI dependencies.
    Dependencies should also be used to implement any preprocessing required before handlers can be safely invoked, such as authorization checks.
    Finally, dependencies should be used for code that would otherwise be duplicated in several handlers, such as setting up logging or extracting information from request headers.

factory
    The factory is responsible for creating services using dependency injection.
    It gathers the config and all of the resources from dependencies and contains the logic for creating service objects, injecting only the resources and configuration that they need.
    It is invoked by the handlers to get the service objects they will call.
    In simpler applications, one can drop the factory and manage the service objects directly via dependencies, but this creates an excessive number of dependencies and tediously long argument lists to handlers in complex applications.

handlers
    FastAPI route handlers.
    The body of these functions should be as small as possible, containing only the minimum code required to create a service, convert the web request into the appropriate model for calling the service, and convert the result of the service into a response (including error handling).
    Most of this work should be handled by FastAPI using Pydantic models for the request and response data.

services
    The service objects are the heart of the application and contain the business logic.
    The methods on service objects are actions: get this, modify that, delete this other thing.
    Those action methods are invoked by handlers or command-line invocations, and take as parameters models that contain the data provided to the request.
    The service object performs that action, possibly using the storage layer to talk to underlying data stores, and returns a result.
    Services are allowed to invoke other services, so there may be several layers of service calls.

storage
    Storage objects are responsible for translating between models and external storage.
    All knowledge of SQL schemas, Redis data structures, LDAP schemas, Kubernetes objects, external REST services, and any other data stores is encapsulated here and never seen by the services layer.
    The storage object performs storage actions, accepting models as parameters, and returns the results converted to models.

    The rule for the storage layer is absolutely no business logic.
    It only translates from models to external storage and only performs those checks that are required by the semantics of the external storage, such as maintaining referential integrity.
    All authorization decisions and business logic decisions are made at the service layer.

Rationale
---------

The two main goals of this application structure are separation of concerns and avoiding code duplication.

For separation of concerns, this structure allows clean separation between the code that converts an HTTP request into an internal call (the handler), the business logic that makes decisions about what should happen (the service), and the code to convert between internal data structures and external storage (the storage object).
Each of these can change independently of the other or gain multiple implementations with minimum impact on the rest of the application.
For example, one could add a command-line interface (or GraphQL interface, gRPC interface, Kafka topic handler, or async worker) that takes some of the same actions as the web UI without duplicating code, since both would call into the services layer.
Or one could replace the database backend with minimum impact on the rest of the application, since all code for dealing with the database is contained in the storage layer.

I've found that this separation of concerns also helps me write better code by focusing my mindset when writing each piece of code.
For example, when writing the storage layer, I am only thinking about referential integrity and correct translation of data types to external storage constructs, not about any of the business logic.
When writing the handler, I am only thinking about translating the web request into an internal call, not about what that call will do.
And when writing the service, I am only manipulating internal data structures designed to precisely reflect the problem domain, without worrying about what web requests look like or how SQL works.
I'm therefore holding less information in my mind at a time, which results in better code.

The factory approach is primarily about avoiding code duplication.
It concentrates all of the code for managing state and building service objects in one place, so that each handler or command-line interface that needs a service object doesn't have to duplicate it.
It also avoids having to manage numerous FastAPI dependencies in each handler, since they can be collected in a factory dependency and the factory will then inject that state into the services as needed.

Finally, this pattern emphasizes dependency injection, which makes it easier to test.
Tests can use a custom factory that uses different external connections or state, storage objects can be replaced with mocks to test the service logic independently, and all of the business logic can be tested directly via service objects without having to set up a web server and make HTTP calls.
It's still often better to write most tests as end-to-end tests using the REST API, since that also tests all of the plumbing, but this design model makes it easier to test edge cases that for one reason or another are difficult to simulate via the REST API.

.. _file-layout:

File layout
===========

Packages follow the layout created by the FastAPI Safir App template, except that they use the pure ``pyproject.toml`` build system configuration with an empty ``setup.cfg``, similar to the `SQuaRE PyPI Package`_ template.
(The empty ``setup.cfg`` appears to currently still be required for application packages.)

.. _SQuaRE PyPI Package: https://github.com/lsst/templates/tree/main/project_templates/square_pypi_package

Any supporting scripts for building the Docker image, and any scripts installed in the Docker image for things like startup are kept in the ``scripts`` directory.
Otherwise, all code is in either ``src/<package-name>`` or ``tests``.

The layout of the Python package roughly matches the components of the architecture described above.
Dependencies go under ``dependencies``, handlers under ``handlers``, middleware (if needed) under ``middleware``, models under ``models``, services under ``services``, and storage objects under ``storage``.

Some additional conventions:

``cli.py``
    Contains the command-line interface to the application, if any.
    If the application has no functionality other than running as a web service, this isn't necessary, since the application is started via uvicorn_ directly.
    But it's often convenient to have a command-line interface to generate secrets or perform other functions.

.. _uvicorn: https://www.uvicorn.org/

    If there is a command-line interface, it should use Click_ with a subcommand structure and a standard ``help`` command
    See `Gafaelfawr's <https://github.com/lsst-sqre/gafaelfawr/blob/6f789ca8be28dc3fa5ccb513588afe06249998ec/src/gafaelfawr/cli.py#L47>`__ for an example.

.. _Click: https://click.palletsprojects.com/en/latest/

    If the application uses SQL storage, the ``init`` command should set up the schema for the application in an empty database.
    Consider implementing a ``delete-all-data`` command to erase the database, since sometimes one wants to reset an installation of the application that uses a cloud SQL database.

    If the application has full documentation, the ``openapi-schema`` command should print the OpenAPI_ schema for its REST interface to standard output (via the ``get_openapi`` function `provided by FastAPI <https://fastapi.tiangolo.com/advanced/extending-openapi/?h=#the-normal-process>`__).
    See :ref:`documentation` for more details.

.. _OpenAPI: https://spec.openapis.org/oas/latest.html

``config.py``
    Contains the configuration parsing code.
    This module should export a ``Config`` (or, in some pre-Python-3.11 cases, ``Configuration``) class that holds all of the application configuration.
    See :ref:`configuration` for details on the two options for application configuration.

``constants.py``
    Any constants used in the application source.
    Collect all of these in one file rather than scattering them through modules unless they are very, very specific to a module and highly unlikely to ever change.
    This file then collects things that may eventually need to become configuration settings.

``exceptions.py``
    Any custom exceptions for this application.
    (Arguably, exceptions could be thought of as models, but I keep them separate because their function in a program is so different than a model.)

    It may be useful to define an exception parent class and then install a global handler for that exception class that generates the correct HTTP error code and body structure.
    Then, all handlers and even services can raise that exception without catching it, and the code to translate it into a valid HTTP error reply can be shared.
    Good candidates for this are a ``ValidationError`` that generates a 422 error compatible with FastAPI and a ``PermissionDeniedError`` that generates a 403 error.

    Exception class names should generally end in ``Error`` (not ``Exception``) following :pep:`8`.

    It's often a good idea to define custom constructors for exceptions that take specific, well-defined, typed data and then construct the human-readable message in the exception code, for better code sharing.

    For exceptions designed to generate structured JSON bodies as part of HTTP errors, define a ``to_dict`` method that translates the exceptions into a dictionary suitable for serializing to JSON.

``factory.py``
    Contains the factory object used to construct services and their dependencies.
    Use of the factory pattern is optional and may not be appropriate for smaller applications.

``main.py``
    Defines the FastAPI application.
    This should either create a global variable named ``app`` or a function named ``create_app``, depending on whether all application initialization can be done at module load time.
    The main case where a ``create_app`` function may be required is if the application object depends on the configuration and the configuration is loaded from a YAML file (see :ref:`configuration`).
    Using a function then allows delaying loading the configuration until a test case has a chance to switch to a different configuration file than the default.

    This module should register all of the routers, set up any middleware, set up any exception handlers, and handle startup and shutdown events.
    Exception handlers can be defined in this same module unless they are complex (they normally won't be).
    The startup and shutdown handlers are conventionally named ``startup_event`` and ``shutdown_event``, respectively, and should handle initializing and closing any dependencies that hold state or external connections.

``util.py``
    Random utility functions used by the rest of the code.
    This should only contain simple functions and should not contain any business logic.
    All business logic should go into a service object instead.
    This is a good place to put Pydantic validators that are shared by multiple models.

If this application uses a SQL database for storage, the SQLAlchemy_ ORM models should go into a directory named ``schema``, and the ``__init__.py`` file for that directory should import all of the models.

.. _SQLAlchemy: https://www.sqlalchemy.org/

If this application includes a Kubernetes operator, the Kopf_ handlers should go into a directory named ``operator``, and the ``__init__.py`` file for that directory should import all of the handlers.
This allows the ``operator`` module to be used as the Kopf entry point.

.. _Kopf: https://kopf.readthedocs.io/en/stable/

.. _configuration:

Configuration
=============

I use two different strategies for configuration: environment variables, or a YAML configuration file.

Environment variables
---------------------

The environment variable approach is used by the FastAPI Safir App template and is preferred for most applications.
Using environment variables makes it very easy to configure through Kubernetes, which has good support for injecting environment variables from secrets and ``ConfigMap`` objects.
With this approach, the ``Config`` class defined in ``config.py`` will look something like this (partial):

.. code-block:: python

   class Config(BaseSettings):
       """Configuration for datalinker."""

       cutout_url: str = Field("", env="DATALINKER_CUTOUT_SYNC_URL")
       """The URL to the sync API for the SODA service that does cutouts."""

Note the default for when the environment variable isn't set.
There should always be a default so that one doesn't have to set environment variables in order to run the test suite, and so that the module load doesn't fail if an environment variable is not set.
It's fine for the default to be invalid and therefore cause failures later if it's not changed, since this still gives the test suite an opportunity to override it.

When using this configuration approach, the ``config.py`` module should then create a global configuration object on module load:

.. code-block:: python

   config = Config()
   """Configuration for datalinker."""

Any part of the application that needs access to the configuration can then use:

.. code-block:: python

   from .config import config

Since everything uses the same global configuration object, that object can be temporarily changed in test fixtures to override some value.
This is the preferred way to set configuration parameters for tests rather than setting environment variables.
For example:

.. code-block:: python

   @pytest_asyncio.fixture
   async def app() -> AsyncIterator[FastAPI]:
       config.tap_metadata_dir = str(Path(__file__).parent / "data")
       async with LifespanManager(main.app):
           yield main.app
       config.tap_metadata_dir = ""

The drawback of this method of configuration is that environment variables cannot easily handle complex data structures.
If the application requires complex data in its configuration, such as nested dictionaries, use the YAML configuration approach instead.

.. _yaml-config:

YAML file
---------

In this model, the application is configured via a YAML file that's mounted into the application container.
The application then uses a dependency to read and cache that file:

.. code-block:: python

   class ConfigDependency:
       def __init__(self) -> None:
           self._config_path = os.getenv("GAFAELFAWR_CONFIG_PATH", CONFIG_PATH)
           self._config: Optional[Config] = None

       async def __call__(self) -> Config:
           return self.config()

       def config(self) -> Config:
           if not self._config:
               self._config = Config.from_file(self._config_path)
           return self._config

       def set_config_path(self, path: str) -> None:
           self._config_path = path
           self._config = Config.from_file(path)


   config_dependency = ConfigDependency()
   """The dependency that will return the current configuration."""

This allows the path to the configuration file to be overridden via an environment variable or via a call to the ``set_config_path`` method (from, say, a command-line flag), which makes it easier to run a local test version of the application.
The test suite can then use ``set_config_path`` to set the configuration path to a file shipped with or generated by the test suite.

The ``from_file`` method on the ``Config`` object would then look something like this:

.. code-block:: python

   @classmethod
   def from_file(cls, path: str) -> Self:
       with open(path, "r") as f:
           return cls.parse_obj(yaml.safe_load(f))

This uses Python 3.11 syntax.
If you need to support older versions of Python, the function should be annotated to return ``Config`` instead.
However, if you also need to use the nested ``Config`` class to configure Pydantic (to support camel-case attributes, for instance), you may need to change the name of your configuration class to ``Configuration`` to avoid naming conflicts with the nested class in the typing of the ``from_file`` function.
This problem goes away with Python 3.11 and the ``Self`` syntax.

I prefer not to mix the environment variable and the YAML file approaches, since I find that confusing.
When using YAML for configuration, I get all of the configuration from the YAML file and not from environment variables.
(A small number of special exceptions can be made if there are specific settings that need to be easily overridden for CI.)

The YAML file approach makes secret handling more difficult.
Kubernetes supports mixing environment variables from secrets and from a ``ConfigMap``, but doesn't support injecting secrets into a ``ConfigMap`` object itself.
This means that the configuration file mounted in the container, which comes from a ``ConfigMap``, cannot easily contain secrets.

There are two possible approaches; mount the secrets as separate files (such as by mounting the entire ``Secret`` resource for the application as a directory) and then put the paths to the secrets into the configuration YAML, or get only the secrets and not any other configuration from environment variables.
The latter is simpler; the former has the advantage that secrets can be injected into complex data structures and portions of the configuration can be passed into specific components.

Gafaelfawr_, which is my one package that uses YAML configuration, uses the first approach and mounts all secrets as separate files.
Its documentation contains `a discussion of the tradeoffs <https://gafaelfawr.lsst.io/dev/configuration.html#passing-secrets>`__.

When using the YAML configuration mechanism, consider reading the configuration into a Pydantic model that does field validation, and then converting the configuration into a nested set of frozen data classes.
This requires repeating some of the configuration data model, but it means that settings can be rearranged, canonicalized, and merged with secrets to create a more coherent internal configuration data structure.

.. _models:

Models
======

FastAPI relies on Pydantic_ for validation and parsing, so all models used by handlers must be Pydantic models.
This includes the models for form submission as well as JSON POST bodies, when form submission has to be supported.
It also includes anything returned by a handler in a response body, including error responses.

.. _Pydantic: https://pydantic-docs.helpmanual.io/

.. _pydantic-models:

Pydantic models
---------------

Since the Pydantic models are used to generate the API documentation, fields in models should always use the ``Field`` constructor and include as much information as possible about that field.
For example:

.. code-block:: python

    name: str = Field(
        ...,
        title="Name of the group",
        example="g_special_users",
        min_length=1,
        regex=GROUPNAME_REGEX,
    )

As shown in this example, make as much use as possible of the built-in validation support in Pydantic so that Pydantic plus FastAPI will do basic validity checks on any user input.

``title`` must always be set to a short English description of the field (no period at the end).
``example`` should normally be set.
If there is a need for longer discussion than will fit in the few words available in ``title``, add ``description``, which can be multiple regular sentences and can even use Markdown formatting if needed.
For example:

.. code-block:: python

    token_type: TokenType = Field(
        ...,
        description=(
            "Class of token, chosen from:\n\n"
            "* `session`: An interactive user web session\n"
            "* `user`: A user-generated token that may be used"
            " programmatically\n"
            "* `notebook`: The token delegated to a Jupyter notebook for"
            " the user\n"
            "* `internal`: A service-to-service token used for internal"
            " sub-calls made as part of processing a user request\n"
            "* `service`: A service-to-service token used for internal calls"
            " initiated by services, unrelated to a user request\n"
        ),
        title="Token type",
        example="session",
    )

As you can see from that example, while FastAPI tries to produce good documentation from enums, it's often not clear enough and one may need to hand-craft a good description.

Any field in a model that takes a limited set of values should be defined as a type inheriting from ``Enum``.
I generally do not make the class also inherit from ``str`` and instead explicitly add ``.value`` to get the string value of an enum.
This ensures that the enum values can't be compared directly to arbitrary strings without mypy complaining, which avoids a class of bugs.
This is a matter of personal taste, however.

There's generally no need for type aliases in models (or elsewhere).

For complex types, ``list`` is fine and ``list[SomeModel]`` or ``list[str]`` is an entirely reasonable type for a model attribute to have.
Be more careful wtih ``dict``.
The rule of thumb is that a ``dict`` type is fine if and only if all keys have the same type and all values have the same type.
So, for instance, ``dict[str, str]`` or ``dict[str, SomeObject]`` is fine, but if the values of the dictionary may have several types or nested structure, use a submodel rather than a dict.

Validators
^^^^^^^^^^

There are often cases where the input from a user won't necessarily be in the same form that the rest of the application expects.
In those cases, use validators to perform the type checking and conversion.

For example, it's more convenient to use :py:class:`datetime.timedelta` for durations, since they can be used in date math with :py:class:`datetime.datetime` objects without further conversion.
But for input, the most convenient duration format is often an integer number of seconds.
The following validator will handle this:

def normalize_timedelta(v: int | None) -> timedelta | None:
    if v is None:
        return v
    elif isinstance(v, int):
        return timedelta(seconds=v)
    else:
        raise ValueError("invalid timedelta (should be in seconds)")

It would then be used as follows:

.. code-block:: python

   class Something:
       lifetime: timedelta = Field(
           ...,
           title="Lifetime in seconds",
           example=3600
       )

       _normalize_lifetime = validator(
           "lifetime", allow_reuse=True, pre=True
       )(normalize_timedelta)

       class Config:
           json_encoders = {timedelta: lambda v: int(v.total_seconds())}

Note the Pydantic configuration for converting :py:class:`datetime.timedelta` back to seconds when returning the model as JSON (in, for example, a response body).

Safir_ comes with `some utility functions for Pydantic <https://safir.lsst.io/user-guide/pydantic.html>`__.
For example, it has a validator to supplement Pydantic's built-in support for parsing some date and time formats to include seconds since epoch and to canonicalize the time zone to UTC.
It can be used as follows (a very partial model):

.. code-block:: python

   from safir.pydantic import normalize_datetime


   class TokenInfo:
       created: datetime = Field(
           default_factory=current_datetime,
           title="Creation time",
           description="Creation timestamp of the token in seconds since epoch",
           example=1614986130,
       )

       last_used: Optional[datetime] = Field(
           None,
           title="Last used",
           description="When the token was last used in seconds since epoch",
           example=1614986130,
       )

       _normalize_created = validator(
           "created", "last_used", allow_reuse=True, pre=True
       )(normalize_datetime)

       class Config:
           json_encoders = {datetime: lambda v: int(v.timestamp())}

Note the syntax for validating multiple fields with the same validator.

Internal models
---------------

For models that are only used internally (such as between services and storage objects) and do not require validation, prefer dataclasses_ to Pydantic models.
Dataclasses are much simpler and signal that none of the complex validation or data transformation done by Pydantic is in play.

.. _dataclasses: https://docs.python.org/3/library/dataclasses.html

As with Pydantic models, use Enum classes for any field that's limited to a specific set of values, and use submodels instead of dictionaries with mixed value types.

Consider marking dataclasses as frozen and creating a new instance of the dataclass whenever you need to modify one.
This makes them easier to reason about and avoids subtle bugs when dataclasses are stored in caches or other long-lived data structures.

Methods on models
-----------------

Models, whether Pydantic or internal dataclasses, are intended only for carrying data from one part of the application to another.
They should never be used to implement business logic or interact with external storage or user input (apart from validation rules).
They are data structures and data containers, not repositories of code.

The one case where methods on models are appropriate is for data conversion.
Use custom constructors (written as class methods) to create a data model object by parsing some other representation of that object.
Add methods starting with ``to_`` to format the contents of the data model into some other representation, such as ``to_dict`` or ``to_cookie``.
(Pydantic provides a built-in ``dict`` method, but sometimes the desired dictionary representation involves some other format conversion that warrants a custom ``to_dict`` method.)

These methods should only do format conversion and input validation, not higher-level verification or business logic such as authorization checks.

.. _factory:

Factory
=======

If an application is at all complex (several services and storage classes, for example, or multiple process-global resources such as database or Redis connection pools, HTTP clients, and so forth), use a factory object to construct service objects.

A basic factory object looks like this (the details of the resources passed in will vary):

.. code-block:: python

   class Factory:
       def __init__(
           self,
           *,
           config: Config,
           session: async_scoped_session,
           logger: BoundLogger,
       ) -> None:
           self._config = config
           self._session = session
           self._logger = logger

       def set_logger(self, logger: BoundLogger) -> None:
           self._logger = logger

You will need to pass in a ``Config`` object if you're using YAML-based configuration (see :ref:`yaml-config`).
With environment-variable-based configuration, you can instead use the global ``config`` object if you want, although it does undermine dependency injection a bit.

The ``set_logger`` function allows you to rebind the logger of an existing factory to include more discovered metadata about a request.
This is useful if you are encapsulating the factory in a ``Context`` object (see :ref:`request-context`), since you can add a function to the ``Context`` object to rebind the logger and have it replace both the logger it stores and the one in the factory for any subsequent objects it creates.

The ``Factory`` class should then have methods for each service object (and in some cases other types of objects) that the application needs to create.
For example:

.. code-block:: python

   def create_some_service(self) -> SomeService:
       storage = SomeStorage(self._config, self._session)
       return SomeService(storage, self._logger)

The factory is responsible for creating the storage objects used by the service and injecting them into the service object as constructor parameters.
Note also how it stores various global and per-context state, such as a bound logger and a database session, and injects them as dependencies where necessary.
See :ref:`dependency-injection` for more details.

You will then create a new ``Factory`` instance for each request, generally via a dependency.
That dependency will depend on other dependencies that provide things like the database session, the logger, and the other objects that need to be injected into the service and storage objects at creation time.
The handlers, in turn, get the factory from a dependency and then call it as needed to create the service objects they need.

The alternative to this factory pattern is to write dependencies that create service objects directly and have handlers depend on those.
That also works, but it can be tedious and awkward to write lots of dependencies in a complex application, as opposed to maintaining one factory class that is made available to every handler via a dependency.
It can also get unwieldy in handlers if a given handler requires a lot of different service objects, which sometimes happens.

Command-line invocations
------------------------

Creating the factory via a dependency works fine for incoming web requests, but if the application also has a command-line interface (to, for example, perform one-off tasks or run background processing), it's awkward to reuse a depedency designed for a web request context to create a factory.

My preferred solution in this case is to add a ``standalone`` class method to the factory that initializes all of the required underlying resources (possibly by calling the internals of various dependencies) and then passes them to the constructor of the ``Factory`` class.
Generally, this method should be decorated with :py:func:`contextlib.asynccontextmanager` and yield the ``Factory`` instance so that it can then do cleanup and shutdown of its various resources (which normally would be done by the FastAPI lifecycle callback).

This class method can then be called from ``cli.py``.
Here's a (simplified) example from Gafaelfawr_:

.. code-block:: python

   @main.command()
   @run_with_asyncio
   async def maintenance() -> None:
       """Perform background maintenance."""
       config = await config_dependency()
       async with Factory.standalone(config) as factory:
           token_service = factory.create_token_service()
           await token_service.expire_tokens()
           await token_service.truncate_history()

Process context
---------------

If you find yourself juggling a ton of process-global resources that have to be drawn from a bunch of separate managing dependencies and passed into the constructor of your ``Factory`` class, it may be worthwhile to bundle them together.

Gafaelfawr_ uses two classes, a ``ProcessContext`` class that holds all the process-global resources that should be initialized once and then reused by every request or operation, and a ``Context`` class that's specifically for a single web request and holds request-specific information.
The ``Context`` object holds the ``ProcessContext`` object and a ``Factory`` instance, and the constructor of the ``Factory`` instance takes a ``ProcessContext`` object plus any additional parameters that are request-specific and need to come from other dependencies.

This allows the ``ContextDependency`` class to provide an ``initialize`` method that does all of the work to set up the ``ProcessContext`` object and cache it so that it can be reused when creating the ``Context`` object for each request.
It's equivalent to having a bunch of separate dependencies caching and managing those global resources, but wraps a container around them so that they're easier to keep track of.

The ``ProcessContext`` class should *only* be used as a convenience for managing the structure of the ``Context`` class and creating the ``Factory`` instance.
Do not succumb to the temptation of passing the ``ProcessContext`` class down into service objects or storage objects.
That looks convenient, but it means you leak lots of global state into every object and it stops being clear which resources a given service or storage class actually needs.
That, in turn, will undermine dependency injection and will make it much harder to write certain classes of tests.

The use of ``ProcessContext``, if you choose to use this pattern, should stop at the ``Factory`` class, and the ``Factory`` class should initialize the objects it creates with only the specific resources they need.

.. _handlers:

Handlers
========

The purpose of a FastAPI handler is to convert an incoming web request into internal models, dispatch it to the services layer, and then format the response (if any) as a correct HTTP response.
Ideally, as much of this as possible should be done by FastAPI rather than hand-written code.
The ideal handler is two lines of code: ask the factory to create the relevant service object, and then call the service object with the input model, returning its result as the output model.

The bulk of the handler should therefore be in the FastAPI decorator and in the parameter list.
FastAPI generates the API documentation from that annotation, so make full use of all of the parameters that flesh out the documentation.
Specifically, every handler should have a ``summary``, many handlers should have a ``responses`` parameter specifying their error codes and descriptions, many handlers should have a ``status_code`` parameter, and larger applications with a lot of handlers should use ``tags``.

Here is an example handler definition that follows those principles:

.. code-block:: python

   @router.get(
       "/users/{username}/tokens",
       response_model=List[TokenInfo],
       response_model_exclude_none=True,
       summary="List tokens",
       tags=["user"],
   )
   async def get_tokens(
       username: str = Path(
           ...,
           title="Username",
           example="someuser",
           min_length=1,
           max_length=64,
           regex=USERNAME_REGEX,
       ),
       auth_data: TokenData = Depends(authenticate_read),
       context: RequestContext = Depends(context_dependency),
   ) -> List[TokenInfo]:
       token_service = context.factory.create_token_service()
       async with context.session.begin():
           return await token_service.list_tokens(auth_data, username)

Note that the body of the handler is only three lines (the second line to do SQL session management using a session-per-request pattern).
The bulk of the code is in the decorator (to add documentation and control the fields returned) and the parameter list (to document the path parameter and require authentication).

This handler uses the :ref:`request-context` pattern.

.. _dependencies:

Dependencies
============

All dependencies, whether standalone functions or ``__call__`` methods on classes, should be async, even if they don't need to be.
Non-async functions require FastAPI to run them in a separate thread pool, since FastAPI doesn't know whether they may block, and thus add overhead and unnecessary complexity.

Holding state
-------------

Dependencies can be used to encapsulate any shared code used by multiple handlers, but one common use of FastAPI dependencies is to encapsulate state.
A dependency has an advantage over a global variable that the state can be loaded lazily on first call or created from an application startup hook, rather than on module load.
This in turn means that the state is automatically recreated between tests, provided that you use the standard ``app`` test fixture, which prevents a lot of problems.

A typical lazily-initialized dependency consists of a class (which holds the state) and an instantiation of that class in a global variable.
For example, here is the basic structure of the Safir-provided ``http_client_dependency``:

.. code-block:: python

   class HTTPClientDependency:
       def __init__(self) -> None:
           self._http_client: Optional[httpx.AsyncClient] = None

       async def __call__(self) -> httpx.AsyncClient:
           if not self._http_client:
               self._http_client = httpx.AsyncClient(
                   timeout=DEFAULT_HTTP_TIMEOUT, follow_redirects=True
               )
           return self._http_client

       async def aclose(self) -> None:
           if self._http_client:
               await self._http_client.aclose()
               self._http_client = None


   http_client_dependency = HTTPClientDependency()
   """The dependency that will return the HTTP client."""

The ``aclose`` method is then called from a shutdown hook to cleanly free the HTTPX client and avoid Python warnings.

The general pattern here is that the constructor creates a private instance variable to hold the state but doesn't initialize it.
The ``__call__`` method initializes that variable if it is ``None`` and then returns its value.
The ``aclose`` method does any necessary cleanup and sets the variable back to ``None``.
This class is then instantiated as a singleton object that is used as a FastAPI dependency.

Conventionally, the class name ends in ``Dependency`` and the singleton object name ends in ``_dependency``.

If the dependency holds something that requires explicit initialization before the first call (usually because it requires parameters, such as from a configuration file that isn't loaded at module load time), add an ``initialize`` method and call that method from the startup hook of the FastAPI service.
The ``__call__`` method should then check that the instance variable has been initialized and raise ``RuntimeError`` if it has not been.

.. _request-context:

Request context
---------------

For complex applications, particularly ones that use the factory pattern to construct service objects, consider creating a "request context" dependency that gathers together various things that handlers may need to use.
Here's a (simplified) example from Gafaelfawr_ of the things included in the request context:

.. code-block:: python

   @dataclass(slots=True)
   class RequestContext:
       request: Request
       """The incoming request."""

       ip_address: str
       """IP address of client."""

       config: Config
       """Gafaelfawr's configuration."""

       logger: BoundLogger
       """The request logger, rebound with discovered context."""

       session: async_scoped_session
       """The database session."""

       factory: Factory
       """The component factory."""

All of these could be provided as separate dependencies, but grouping them into one dependency avoids writing tedious parameter lists for each handler.
It also allows the context object to provide some extra functionality, such as rebinding the structlog_ logger with additional context discovered by the handler or its other dependencies.
The request context dependency can also (as here) be responsible for constructing the factory object that's then used to create service objects.

.. _services:

Services
========

The service layer is where all the business logic of the application should live.
Business logic is the core work that the application is trying to perform, separated from how that work is requested (the UI, implemented by the request handlers and possibly CLI code) and how data is stored and retrieved (the storage layer).

All input and output data from the service layer should be either simple types or models.
The layers above and below that layer are responsible for converting those models to other formats for talking to the rest of the world.

The purpose of this layered model is complexity isolation.
The service layer is the most critical part of that layering, and its API deserves some careful thought.
In general, the API exposed by the service layer should consist of commands: "get a matching object," "create a resource for this user," or "delete data with this key."
Sometimes it may include questions: "is this user an administrator."

The method names of the API will therefore look like ``get_user`` or ``create_lab``.
The arguments to the method should fully specify the object to retrieve or act on without providing more complex data than is necessary.

So, for example, when creating a resource for a specific user, an appropriate signature would be something like this:

.. code-block:: python

   async def create_resource(self, username: str) -> Resource: ...

In this case, only the username is required to create the resource.
If the handler has a full data structure about the user, it should *not* pass in the entire user model just because it's convenient, unless most of that data will be used.
Instead, it should pass in only the username, so that it's obvious at both the call site and the implementation site that only the username is needed or used.

This may seem like a minor and tedious point, but strictly following this design for a minimal API that clearly advertises what data it uses and acts on will help keep complexity isolated and contained within the application.

.. _dependency-injection:

Dependency injection
--------------------

All service objects should use `dependency injection`_.
This means that any other objects that a service object needs to call should be passed into its constructor, not created in its constructor.
This aids with testing and complexity isolation.

.. _dependency injection: https://www.jamesshore.com/v2/blog/2006/dependency-injection-demystified

Similar to the principal above for methods, those objects should be passed in individually, not in a container object with lots of objects that may or may not be needed by this service.

The most common dependencies injected into a service object are storage objects, the application configuration (or some subset of it), and internal process-wide caches (if they are simple enough to not warrant their own storage layer to manage them).

It helps code clarity immensely to maintain a clear mental separation between *dependencies* (code and other objects that the service object needs to do its work) and *parameters* (the instructions for what work to do).
The former should be injected into the constructor when the service object is created.
The latter should be passed into the service object method as part of the API call.

One helpful way to think of this distinction is that dependencies are general facilities of the application (even if they're created anew with each request), whereas method parameters are details from the specific request or command-line invocation being processed.

.. _storage:

Storage
=======

The storage layer is responsible for converting internal models into the format required to store them somewhere else.
That "somewhere else" could be a SQL database, Redis, another web service with an API, or even an internal in-memory cache.

The rule for the storage layer is absolutely no business logic.
The sole responsibility of the storage layer is to take a model or simple types from the service layer and perform an operation: store data, retrieve data (and return it as a model), delete data, and so forth.
It may also encapsulate more complex storage operations, such as complex SQL searches, but it should not make any decisions.
The storage layer should be a possibly-complex but purely mechanical conversion of the operation the service layer wants to perform into the language or operations required to perform it.

This means the storage layer may do syntax checks if required to safely store data, and may enforce such things as referential integrity.
But it shouldn't do any authorization checks, it shouldn't manipulate the data beyond the translation required to convert to and from internal models, and it shouldn't make any decisions about what data should be stored.
All of that is the business of the service layer.

The storage layer should generally only be called by the service layer.
Even in cases where the service layer has nothing to do, I add a pass-through API to the service layer to maintain this invariant.

.. _testing:

Testing
=======

Always use pytest_ for testing.
Always use the function and fixture approach.
Never use ``unittest``-style classes.

.. _pytest: https://docs.pytest.org/en/latest/

The "don't repeat yourself" rule is relaxed for tests in favor of making each test case obvious and straightforward.
It's okay to cut and paste input data and expected results with minor variations.
This is preferrable over being too fancy with templating or dynamically-generated code.
Do not create a situation where debugging the logic of the test is harder than debugging your actual application, or where application bugs are masked by test bugs from over-complicated test logic.

Naming
------

Organize the tests according to the entry point of the application invoked.
For example, tests that create the full FastAPI application and interact with its routes go into a ``tests/handlers`` directory.
Tests that create a service object and interact with it directly go into the ``tests/services`` directory.
Most tests will be in ``tests/handlers``; this is fine.

The ``tests`` directory and every subdirectory must have an empty ``__init__.py`` file so that mypy works correctly.

Files containing tests should always end in ``_test.py`` and should never start with ``test_``.
This makes tab completion on file names more useful.
As a first rough guide, put tests into files matching the name of the source file primarily being tested, but feel free to deviate from this guideline to break up large files of tests into ones grouped by subject matter.

Fixtures and support code
-------------------------

Fixtures should generally be collected into a ``tests/conftest.py`` file.
Avoid fixtures in individual test files; they're easy to forget about and thus not reuse in other tests even when they would be helpful.
If there are a set of fixtures that are very specific to tests for only one part of the application, such as Kubernetes fixtures for a ``tests/operator`` directory full of tests for a Kopf_ Kubernetes operator, put them in a ``conftest.py`` file in that directory so that they're isolated to those tests.

To clean up after tests that need external resources or modify global state, use `yield fixtures <https://docs.pytest.org/en/latest/fixture.html#yield-fixtures-recommended>`__.
Set up the resource or global state in the fixture, yield (it's okay to yield ``None`` and is often appropriate if the fixture doesn't need to provide a value to the test), and then close any resources and put any global state back the way it was.

Prefer per-test fixtures, but feel free to use session fixtures in places where it substantially speeds up the test suite (but be careful to avoid leaking state from one test to the next).

Put support code for tests in modules under ``tests/support``.
There should be no actual tests in that directory, only support code for other tests.
Any test support code used in more than one test should go into that directory, and feel free to move support code used by only one test file as well if it seems clearer.

Try to keep the code in fixtures as short as possible.
Prefer to put the bulk of the code under ``tests/support`` and have the fixture call a function or use an object defined there.

Test data
---------

Prefer storing test data in files under the ``tests`` directory in an appropriately-named subdirectory over embedding test data in long strings inside test cases.
Test data can then be loaded with code such as:

.. code-block:: python

   data_path = Path(__file__).parent.parent / "data" / "some-data-file.txt"
   data = data_path.read_text()

.. _third-party:

Preferred third-party libraries
===============================

In general, use Safir_ whenever it provides necessary functionality, and use whatever underlying libraries it supports.
This includes HTTPX_ for HTTP clients, structlog_ for logging, and arq_ for work queues.

.. _Safir: https://safir.lsst.io/
.. _HTTPX: https://www.python-httpx.org/
.. _structlog: https://www.structlog.org/en/stable/
.. _arq: https://arq-docs.helpmanual.io/

For other cases, prefer the listed PyPI libraries:

.. rst-class:: compact

- **Command line**: Click_
- **Kubernetes**: kubernetes_asyncio_ and, for Kubernetes operators, Kopf_
- **LDAP**: bonsai_
- **Redis**: aioredis_
- **SQL**: SQLAlchemy_ (use the 2.0 API with async) and asyncpg_
- **Templating**: Jinja_
- **YAML**: PyYAML_ if preserving comments and order isn't required, otherwise ruamel.yaml_.

.. _kubernetes_asyncio: https://github.com/tomplus/kubernetes_asyncio
.. _bonsai: https://bonsai.readthedocs.io/en/latest/
.. _aioredis: https://aioredis.readthedocs.io/en/latest/
.. _asyncpg: https://magicstack.github.io/asyncpg/current/
.. _Jinja: https://jinja.palletsprojects.com/en/latest/
.. _PyYAML: https://pyyaml.org/
.. _ruamel.yaml: https://yaml.readthedocs.io/en/latest/

.. _coding-style:

Coding style
============

In general, coding style follows :pep:`8` as enforced by flake8_ and Black_, using the standard configuration from the Safir FastAPI App template.
Here are some additional, somewhat random notes.

.. _flake8: https://flake8.pycqa.org/en/latest/
.. _Black: https://black.readthedocs.io/en/stable/

Typing
------

- Do not use ``from __future__ import annotations`` in any file that defines FastAPI handlers or dependencies.
  If you don't follow this rule, you will run into bizarre and hard-to-understand problems because FastAPI relies heavily on type annotations and cannot do the analysis it needs to do when this feature is enabled.
  You can still use this directive in other files, such as services, storage modules, and models.
  If you need a forward type reference in a file that defines a dependency or handler (this is rare and, except in alternate constructors, probably a sign you have code you should move to a model or a service), quote the reference instead of using this directive.
  If you can switch to Python 3.11 or later, the ``Self`` type may do what you want.

- All code should be fully typed using mypy.
  Use ``TypeVar`` and bound types to type function decorators and generics as tightly as possible and avoid losing type information.
  For helper functions that return ``None`` only if the input is ``None``, use ``@overload`` to tell mypy about those sematics and avoid a generic ``Optional`` return type.
  When retrieving objects from places where they lose type information (such as the `Kopf memo data structure <https://kopf.readthedocs.io/en/stable/memos/>`__, immediately assigned them to a variable with an explicit type so that the rest of the code gets the benefit of strong type checking.

- In cases where you know that a value is not ``None`` but mypy cannot figure this out, add an explicit test and raise ``RuntimeError`` if the value is ``None``.
  However, this case usually indicates a correctable flaw in the type system, and a more careful design of types usually allows removing the ``Optional`` annotation.
  Sometimes this will require using type inheritance and multiple classes instead of a single class where some parameters or internal data types are marked ``Optional``.

- Avoid ``Union`` types.
  They are usually not necessary and add considerable complexity to the signatures and type-checking of surrounding code.
  Instead, be more opinionated about the correct type and convert to that type earlier.
  In the rare case where they are appropriate, such as models with two mutually-exclusive options, use the ``|`` syntax instead of the ``Union`` syntax (unless you have to support Python 3.9 for some reason).

- Prefer ``list`` and ``dict`` to ``List`` and ``Dict``, and similarly for all of the other deprecated types listed in :pep:`585`.
  Note that many types (such as ``AsyncIterator``, ``Iterable``, and ``Mapping``) should be imported from ``collections.abc`` and not ``typing``.

- Whether to use ``Optional[str]`` or ``str | None`` is to some extent a matter of taste (unless you have to support Python 3.9 or earlier).
  My rule is that optional parameters to functions, optional attributes for models, and placeholder values (such as in the constructor of an object that must be initialized before being used) are annotated with ``Optional``.
  All return values, any place where the argument is required but still may be ``None``, use the ``str | None`` syntax instead.

Data types
----------

- As in :ref:`pydantic-models`, dictionaries should only be used in cases where all the keys have a single type and all the values have a single type.
  Dictionaries with mixed value types are only appropriate as short-lived intermediate forms before, for example, JSON or YAML encoding.
  Prefer internal models in all other cases where a dictionary might be used, particularly when data is being passed into or returned from a function.
  Convert data to the internal model as early as possible and back to a more generic format as late as possible.
  (There is no need to avoid use of lists, or of dictionaries with consistent types.)

- All times internally should be represented as ``datetime`` objects in the UTC time zone.
  Convert requests to this format and responses from this format using Pydantic validators and JSON encoders.
  Convert to non-timezone-aware UTC date-time SQL types for database storage in the storage layer, using `Safir functions <https://safir.lsst.io/user-guide/database.html#handling-datetimes-in-database-tables>`__.
  Use the `Safir validator <https://safir.lsst.io/user-guide/pydantic.html#normalizing-datetime-fields>`__ to validate and canonicalize ``datetime`` objects in models.

- Differences between times, including usually in constants, should be represented as ``timedelta`` objects rather than an integer number of seconds, minutes, etc.
  The one exception is if the constant is used as a validation parameter in contexts (such as some Pydantic and FastAPI cases) where a ``timedelta`` is not supported.

- Always use pathlib_ for any file paths.
  Never use os.path_ functions.
  If necessary for external APIs, convert ``Path`` objects to strings with ``str()`` when passing them to external methods or functions.
  For internal APIs and internal models, always take a ``Path`` object rather than a ``str`` when accepting a file path.

.. _pathlib: https://docs.python.org/3/library/pathlib.html
.. _os.path: https://docs.python.org/3/library/os.path.html

Modules
-------

- Always use relative imports for anything contained in the same package.
  Use absolute imports of package modules from the test suite, and use relative imports inside the test suite of test suite support code.

- The public API of a module (only and exactly those symbols used by other modules) should be listed in ``__all__``.
  This is required if you are building :ref:`internal API documentation <api-documentation>` because the Sphinx ``automodapi`` plugin uses ``__all__`` to determine what to generate documentation for.

- Functions and variables used only within a module should be prefixed with ``_``, just like private methods (see :ref:`style-classes`).

.. _style-classes:

Classes
-------

- Put a single underscore (``_``) in front of methods and instance variables that are internal to the class to mark them private.
  All instance variables of normal (non-model) objects should normally be internal to the class.

  No private methods or instance variables should be used outside of the class.
  A special exception can be made for tests, although even there it's usually preferrable to add special methods for tests and document them as only being useful for testing.

- Do not use Pydantic models or dataclasses for normal objects that encapsulate behavior and resources, such as services or storage objects.
  Models and dataclasses declare that all of their data is public and that anyone in possession of an object should feel free to read or modify the data directly.
  This is the opposite of the behavior represented by a traditional object, where the object should only be used via its public methods and the purpose of the object is to hide the complexity of its implementation and underlying data.

- Classes that have an async teardown method that frees resources stored in the class should name that method ``aclose`` (not ``close``).
  This makes the class compatible with `contextlib.aclosing <https://docs.python.org/3/library/contextlib.html#contextlib.aclosing>`__.

- Classes that represent background processing, rather than a resource container, should have ``start`` and ``stop`` methods to start and stop that processing rather than using ``aclose``.

Methods and functions
---------------------

- If a method or function takes more than three parameters, not including the ``self`` or ``cls`` parameter, make at least some of those parameters require the parameter name by putting them after ``*``.
  For cases where all the parameters are mandatory, such as many constructors, put all the parameters after ``*``.
  For cases where some of the parameters are optional and not always given, and there are three or fewer mandatory parameters, you can instead put only the optional parameters after ``*``, or use some mix that makes sense (taking into account the next rule).

- Whenever the meaning of a method or function parameter is not obvious in context at the call site, put that parameter after ``*`` so that the parameter name is mandatory.
  A common case of this is boolean parameters, which should almost always be listed after ``*`` because the meaning of a bare ``True`` or ``False`` is usually inobvious at the call site.

- Use ``to_`` as a prefix for methods that convert a data object's contents to another format (such as ``to_dict`` or ``to_header``).
  Use ``from_`` as a prefix to class methods that create a data object from some other data source (such as ``from_cookie`` or ``from_str``).

- Consider using ``is_`` as a prefix for boolean functions or methods that answer yes-or-no questions about their arguments or the object on which they're defined.
  Don't use ``is_`` as a prefix for a function or method that returns something other than a boolean.

Docstrings
----------

- Write docstrings following the `Rubin project recommendations <https://developer.lsst.io/python/numpydoc.html>`__.
  (As of this writing, this guide does not yet recommend omitting types from the docstrings, which is now better style when using current Sphinx.
  This is likely to be updated soon.)

- Contrary to the above style guide, I restrict the first, summary line of any docstring to fit entirely on one line.
  This is just personal preference; to me, wrapped summary lines look awkward and haven't felt necessary.

- All modules, classes, public methods of classes and instances, functions, and constants should have full docstrings following the above style.
  Modules that provide only a single class usually only need a one-line docstring, since the bulk of the useful documentation goes into the class and doesn't need to be repeated.

  Private methods should still have docstrings and may have full docstrings, but it's okay to be looser and to omit documentation (parameters and returns, for example) that doesn't add much value or that feels obvious in context, since the docstrings of private methods will only be read by someone already reading the full source.
  Test fixtures and helper functions are similar to private methods in this respect.

  Tests should never document their parameters (which will all be fixtures with their own documentation anyway), but may contain a docstring if it's not obvious what the test is testing.

- Docstrings are for callers and internal comments are for editors.
  If there is some subtlety to the implementation or approach of a method, but the caller doesn't need to know about it, put that information in a comment instead of in the docstring.

.. _documentation:

Documentation
=============

Only a few applications are complex enough to warrant a full manual, but every application should have some documentation.
Here are the options in descending order of number of applications that will need this type of documentation.

Don't put comprehensive documentation in the ``README.md`` file of the application repository itself.
Instead, stick to a brief description of the application and link to the other documentation sources mentioned here.

API documentation
-----------------

All applications with a REST interface should expose their API documentation.
This is done automatically by FastAPI, although you may need to adjust the URLs it uses.
The FastAPI Safir App template will set up appropriate URLs and include a default application description from the project metadata.

FastAPI provides both Swagger-generated documentation and Redoc-generated documentation.
Both of these are better at some things and worse at others.
Swagger allows experimentation with the API from inside the documentation, which Redoc does not.
Redoc has (in my opinion) better formatting and more complete information about the parameters.
Redoc is also easier to embed in a full manual (see :ref:`manual`).

The raw OpenAPI specification will also be available at ``/openapi.json`` under the application root.
Ensure that this URL is available, since eventually it will be used by Squareone_ to provide merged API documentation for the Rubin Science Platform.

.. _Squareone: https://github.com/lsst-sqre/squareone

Phalanx
-------

Any application deployed via Phalanx will get an entry in the applications section of the `Phalanx documentation`_.
For many internal components, this is all the documentation that's needed.

.. _Phalanx documentation: https://phalanx.lsst.io/

For any application, this is the right place for operational documentation in the context of the Science Platform, troubleshooting, bootstrapping considerations, and details about how the application is configured differently in different environments.

If you write any of the below types of documentation, ensure there's a link to that documentation here.

.. _technote:

Tech notes
----------

For any significant component of the Science Platform, and for most internal applications, I try to write a tech note.

The purpose of the tech note isn't to explain how to use the application.
Instead, it's to describe the problem that it was trying to solve (the requirements), the approach we took to solving that problem, any non-obvious technical decisions and what alternatives we considered, and any future work.
The intended audience for the tech note is other sites or other project members trying to understand what we did, and any future maintainer of the application who needs to understand the underlying design principles and tradeoffs.

Most applications will have a single tech note.
Some larger applications may benefit from having separate tech notes for the overall design and for the implementation details.
The target audience for the first tech note would be people who want to know how the system works at a high level and what users of the Science Platform would see, distinct from the target audience for the second tech note, which is people working on the implementation.

In particularly complex cases, it may also be a good idea to split the second tech note into one, kept-up-to-date tech note on the current implementation approach without all the blind alleys and failed experiments, and a second tech note that goes into detail about all the approaches that were tried and abandoned, and all the implementation decisions made along the way.

Use ``DMTN`` tech notes if the tech note will need a reviewer outside of the SQuaRE team.
For example, design documents for VO services that will be reviewed by the product owner should use the ``DMTN`` series.
Use ``SQR`` tech notes for internal applications, implementation documents, and other designs that do not need to be reviewed outside of SQuaRE.

For an example of a complex tech note series with all three of those types of tech notes, see the Gafaelfawr tech notes: :dmtn:`234`, :dmtn:`224`, and :sqr:`069`.

.. _manual:

Manual
------

Some larger applications, or applications that may be used outside of the Science Platform, may benefit from a full user manual.

In this case, the manual should use the `Rubin user guide <https://documenteer.lsst.io/guides/index.html>`__ pattern following the Documenteer documentation.
The manual source, as mentioned in that guide, should go in the ``docs`` directory.
It should be published via GitHub Actions using LSST the Docs and its GitHub action.
For an example, see the `Gafaelfawr configuration <https://github.com/lsst-sqre/gafaelfawr/blob/6f789ca8be28dc3fa5ccb513588afe06249998ec/.github/workflows/ci.yaml#L121>`__.

The user manual should not duplicate the Phalanx documentation or the tech notes.
Its focus should be on explaining to a user how to configure and use the application, and to a potential developer how to modify the application.
If the application has a full manual, it may make sense to move most of the configuration documentation from the Phalanx docs to that manual, link to the manual from the Phalanx docs, and keep the Phalanx guides limited to only Phalanx-specific configuration and troubleshooting.

All reStructuredText in the manual should use one sentence per line rather than wrapped text.
(This makes diffs of the manual more useful and therefore aids code review.)

REST API documentation
^^^^^^^^^^^^^^^^^^^^^^

If the application has a manual, it's a good idea to embed the REST API documentation in the manual so that a user doesn't have to find a running instance to view the documentation.

Unfortunately, none of the mechanisms for doing this that I've found are wholly satisfactory.
The `Swagger extension to Sphinx <https://pypi.org/project/sphinx-swagger/>`__ appears to no longer be maintained.
The `OpenAPI extension <https://github.com/sphinx-contrib/openapi>`__ also hasn't been updated recently and didn't work when I tried it.
I landed on `sphinxcontrib-redoc <https://sphinxcontrib-redoc.readthedocs.io/en/stable/>`__, which does work, but unfortunately doesn't incorporate the documentation into the manual as seamlessly as I'd like.

That extension takes the ``openapi.json`` file as input, so you will need a command-line interface to the application to generate that file.
See `the Gafaelfawr version <https://github.com/lsst-sqre/gafaelfawr/blob/6f789ca8be28dc3fa5ccb513588afe06249998ec/src/gafaelfawr/cli.py#L234>`__ for an example that you can customize for your application.
Note the code there to add a back link to the rest of the documentation.
Unfortunately, sphinxcontrib-redoc generates a standalone page, so users will be stranded on that page unless you manually add a back link.

You will then need to invoke that command before building the docs (as part of your ``docs`` tox environment, for instance).
Then, use a stanza like this in ``docs/conf.py``:

.. code-block:: python

   redoc = [
       {
           "name": "REST API",
           "page": "rest",
           "spec": "_static/openapi.json",
           "embed": True,
           "opts": {"hide-hostname": True},
       }
   ]
   redoc_uri = (
       "https://cdn.jsdelivr.net/npm/redoc@next/bundles/redoc.standalone.js"
   )

Finally, there's no way to include this generated page directly in the Sphinx user guide navigation, unfortunately, so you'll need a stub rST page that links to it.
I include that page in the top-level navigation bar as "REST API".

.. code-block:: rst

   ########
   REST API
   ########

   Once Gafaelfawr is installed, API documentation is available at
   ``/auth/docs`` and ``/auth/redoc``.  The latter provides somewhat more
   detailed information.

   You can view a pregenerated version of the Redoc documentation for the
   current development version of Gafaelfawr by following the link below.

   `REST API <rest.html>`__

(Lines have been wrapped to make the code sample more readable in this tech note, but normally this would use the one line per sentence convention.)

.. _api-documentation:

Internal API documentation
^^^^^^^^^^^^^^^^^^^^^^^^^^

While this is completely optional, if I am building a manual for an application anyway, I like to include internal API documentation.
This is less important than for a library, since only developers of the application will care about the documentation, but I still find it potentially useful to help a new developer get oriented.
Besides, I'm writing the docstrings anyway, so including them in a manual isn't very much work.

The target audience for internal API documentation is only developers, not users, so it should go into the developer section of the user guide.
By convention, I use ``docs/dev/internals.rst`` as the top-level page with the automodapi_ directives.

.. _automodapi: https://sphinx-automodapi.readthedocs.io/en/latest/

Do not include the handlers in the internal API documentation.
They won't generate useful entries, and you should not write docstrings for handler functions.
(They would be redundant with the FastAPI decorator.)

Also do not include ``cli.py`` if you have one.
Instead, use sphinx-click_ to generate documentation for the command-line interface.

.. _sphinx-click: https://sphinx-click.readthedocs.io/en/latest/

.. _changelog:

Change log
^^^^^^^^^^

Any application that has a manual should probably also have a change log.
The change log is maintained in ``CHANGELOG.md`` at the top level of the repository, in Markdown format.
It should summarize user-visible changes from the previous release.

Each entry should use the following layout:

.. code-block:: markdown

   ## X.Y.Z (YYYY-MM-DD)

   ### Backward-incompatible changes

   - Some change.

   ### New features

   - Some change.

   ### Bug fixes

   - Some change.

   ### Other changes

   - Some change.

Omit any sections that are not needed.
There will only be backward-incompatible changes for major version bumps and new features for minor version bumps (see :ref:`releases` for more about versioning).

Unlike the normal convention of one sentence per line, each change log bullet point, no matter how many sentences long, should be a single line.
This allows the change log to be cut and pasted into the text box for the GitHub release description with no formatting changes.

While a release is still being prepared, the date in the version header should instead be ``(unreleased)``.
Write new change log entries and update the version number based on semantic versioning as changes are merged to save time and ensure a complete change log when preparing the release.

.. _releases:

Releases
========

Default to making a new release of the application after every noticable change, including bug fixes.
Releases are cheap; follow the release early, release often principle.

Each release should publish a Docker image to the GitHub Container Registry.
(This is generally done via the GitHub Actions configuration provided by the FastAPI Safir App template.)
Also publishing the container to the Docker Hub registry is not necessary.

Use `Semantic Versioning`_ versioning.
I'm strict about this: every backwards-incompatible change bumps the major version and every new feature bumps the minor version.
This means that my version numbers tend to increase faster than a lot of open source software.
This is fine.

.. _Semantic Versioning: https://semver.org/

Each release should is marked with a Git tag matching the version number (with no leading ``v``).
The FastAPI Safir App template uses setuptools_scm_ to generate the application version, which will take the version from the Git tag.

.. _setuptools_scm: https://github.com/pypa/setuptools_scm

Each release should also be a GitHub release made at the same time.
The title of the release should also be the version number.

The body of the release should be the :ref:`changelog` entry for that release if the application maintains a change log.
If not, it should be a human-readable description of the changes in that release, generally as a bullet list.
Omit routine updates to the package dependencies and similar housekeeping that doesn't result in user-visible changes to application behavior.

If you follow the formatting conventions documented in :ref:`changelog`, you can cut and paste the change log entry into the text box for the release description in the GitHub web interface.
