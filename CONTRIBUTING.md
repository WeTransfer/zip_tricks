# Contributing to zip_tricks

Please take a moment to review this document in order to make the contribution
process easy and effective for everyone involved.

Following these guidelines helps to communicate that you respect the time of
the developers managing and developing this open source project. In return,
they should reciprocate that respect in addressing your issue or assessing
patches and features.

## What do I need to know to help?

If you are already familiar with the [Ruby Programming Language](https://www.ruby-lang.org/) you can start contributing code right away, otherwise look for issues labeled with *documentation* or *good first issue* to get started.

If you are interested in contributing code and would like to learn more about the technologies that we use, check out the (non-exhaustive) list below. You can also get in touch with us via an issue or email to get additional information.

 - [ruby](https://ruby-doc.org)
 - [rubyzip](https://github.com/rubyzip/rubyzip)
 - [rspec](http://rspec.info/) (for testing)
 - [zip files](https://en.wikipedia.org/wiki/Zip_(file_format))

# How do I make a contribution?

## Using the issue tracker

The issue tracker is the preferred channel for [bug reports](#bug-reports),
[feature requests](#feature-requests) and [submitting pull
requests](#pull-requests), but please respect the following restrictions:

* Please **do not** derail or troll issues. Keep the discussion on topic and respect the opinions of others. Adhere to the principles set out in the [Code of Conduct](https://github.com/WeTransfer/zip_tricks/blob/main/CODE_OF_CONDUCT.md).

## Bug reports

A bug is a _demonstrable problem_ that is caused by code in the repository.

Good bug reports are extremely helpful-thank you!

Guidelines for bug reports:

1. **Use the GitHub issue search** &mdash; check if the issue has already been
   reported.

2. **Check if the issue has been fixed** &mdash; try to reproduce it using the
   latest `main` branch in the repository.

3. **Isolate the problem** &mdash; create a [reduced test
   case](http://css-tricks.com/reduced-test-cases/) and a live example.

A good bug report shouldn't leave others needing to chase you up for more
information. Please try to be as detailed as possible in your report. What is
your environment? What steps will reproduce the issue? What tool(s) or OS will
experience the problem? What would you expect to be the outcome? All these
details will help people to fix any potential bugs.

Example:

> Short and descriptive example bug report title
>
> A summary of the issue and the OS environment in which it occurs. If
> suitable, include the steps required to reproduce the bug.
>
> 1. This is the first step
> 2. This is the second step
> 3. Further steps, etc.
>
> `<url>` - a link to the reduced test case, if possible. Feel free to use a [Gist](https://gist.github.com).
>
> Any other information you want to share that is relevant to the issue being
> reported. This might include the lines of code that you have identified as
> causing the bug, and potential solutions (and your opinions on their
> merits).


## Feature requests

Feature requests are welcome. But take a moment to find out whether your idea
fits with the scope and aims of the project. It's up to *you* to make a strong
case to convince the project's developers of the merits of this feature. Please
provide as much detail and context as possible.


## Pull requests

Good pull requests-patches, improvements, new features-are a fantastic
help. They should remain focused in scope and avoid containing unrelated
commits.

**Please ask first** before embarking on any significant pull request (e.g.
implementing features, refactoring code, porting to a different language),
otherwise you risk spending a lot of time working on something that the
project's developers might not want to merge into the project.

Please adhere to the coding conventions used throughout the project (indentation,
accurate comments, etc.) and any other requirements (such as test coverage).

The project uses Rubocop which can be run using `bundle exec rubocop`. The test
suite can be run with `bundle exec rspec`. You are also encouraged to use the
script in the `testing` directory to create test files that you can then verify
with various zip/unzip utilities. Further instructions are [here](https://github.com/WeTransfer/zip_tricks/blob/main/testing/README_TESTING.md).  

Follow this process if you'd like your work considered for inclusion in the
project:

1. [Fork](http://help.github.com/fork-a-repo/) the project, clone your fork,
   and configure the remotes:

   ```bash
   # Clone your fork of the repo into the current directory
   git clone git@github.com:WeTransfer/zip_tricks.git
   # Navigate to the newly cloned directory
   cd zip_tricks
   # Assign the original repo to a remote called "upstream"
   git remote add upstream git@github.com:WeTransfer/zip_tricks.git
   ```

2. If you cloned a while ago, get the latest changes from upstream:

   ```bash
   git checkout <dev-branch>
   git pull upstream <dev-branch>
   ```

3. Create a new topic branch (off the main project development branch) to
   contain your feature, change, or fix:

   ```bash
   git checkout -b <topic-branch-name>
   ```

4. Commit your changes in logical chunks and/or squash them for readability and
   conciseness. Check out [this post](https://chris.beams.io/posts/git-commit/) or
   [this other post](http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) for some tips re: writing good commit messages.

5. Locally merge (or rebase) the upstream development branch into your topic branch:

   ```bash
   git pull [--rebase] upstream <dev-branch>
   ```

6. Push your topic branch up to your fork:

   ```bash
   git push origin <topic-branch-name>
   ```

7. [Open a Pull Request](https://help.github.com/articles/using-pull-requests/)
    with a clear title and description.

**IMPORTANT**: By submitting a patch, you agree to allow the project owner to
license your work under the same license as that used by the project, which you
can see by clicking [here](https://github.com/WeTransfer/zip_tricks/blob/main/LICENSE.txt). 
