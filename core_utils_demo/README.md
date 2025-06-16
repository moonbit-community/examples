# Develop Core Utils in MoonBit

## Introduction

This project is for exploring how MoonBit can implement the core utils with its
native backend. We aim to show what MoonBit can do and what are the obstacles in
the procedure.

## Background

We will be using native backend of MoonBit, which can link to native libraries
with FFIs. In this case, we will be using `uv.mbt`, a project that provides
binding to [libuv](https://libuv.org).

The reason for choosing it is that it is cross-platform, and it provides many
operations, including manipulating files and processes.

## Core Utils

We will try to implement the following ones:

- cat: concat multiple files
- ls: list directory
- tree: display the directory structure as a tree
