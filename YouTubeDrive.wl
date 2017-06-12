(* ::Package:: *)

(* :Title: YouTubeDrive *)
(* :Context: YouTubeDrive` *)
(* :Author: David K. Zhang *)
(* :Date: 2017-06-11 *)

(* :Package Version: 1.0 *)
(* :Wolfram Language Version: 11.0 *)

(* :Summary: YouTubeDrive is a Wolfram Language package that encodes/decodes
             arbitrary ByteArray data to/from simple RGB videos stored on
             YouTube. Since YouTube imposes no limits on the total number or
             length of videos users can upload, this provides an effectively
             infinite but extremely slow form of file storage.

             YouTubeDrive depends externally on FFmpeg (https://ffmpeg.org/),
             youtube-upload (https://github.com/tokland/youtube-upload), and
             youtube-dl (https://rg3.github.io/youtube-dl/). These programs
             are NOT included with YouTubeDrive, and MUST be downloaded and
             installed separately. See below for details.

             YouTubeDrive is a silly proof-of-concept, and I do not endorse
             its high-volume use. *)

(* :Copyright: (c) 2017 David K. Zhang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. *)


BeginPackage["YouTubeDrive`"];


YouTubeUpload::usage = "YouTubeUpload[bytearr] encodes a bytearray bytearr as \
a simple RGB video, uploads the video to YouTube, and returns the resulting \
video ID.";

YouTubeUpload::nbarr = "The first argument of YouTubeUpload must be a \
ByteArray object.";


YouTubeRetrieve::usage = "YouTubeRetrieve[videoid] retrieves the YouTube video
with video ID videoid, decodes it, and returns the resulting data as a \
ByteArray object.";

YouTubeRetrieve::dlerr = "YouTubeRetrieve was unable to download the \
requested video with ID `1`. Make sure that this is a valid video ID, \
and that the associated video is publicly viewable in your region.";

YouTubeUpload::nbarr = "The first argument of YouTubeRetrieve must be a \
string.";


Begin["`Private`"];

(* After installing FFmpeg, youtube-upload, and youtube-dl, set the following
   variables to the install locations of the corresponding programs. *)
FFmpegExecutablePath = "FFMPEG_PATH_HERE";
YouTubeUploadExecutablePath = "YOUTUBE-UPLOAD_PATH_HERE";
YouTubeDLExecutablePath = "YOUTUBE-DL_PATH_HERE";


YouTubeUpload[data_ByteArray] := Module[{
  numBytesPerRow = 24, numRowsPerFrame = 36, tempDir = CreateDirectory[],
  numRows, numLeftoverBytes, numFrames, numLeftoverRows, numDigits,
  row, frame, finalFullRows, leftoverBits, finalPartialRow, finalFrameData,
  finalFrame, i, procInfo},

  SetDirectory[tempDir];

  {numRows, numLeftoverBytes} = QuotientRemainder[Length[data], numBytesPerRow];
  {numFrames, numLeftoverRows} = QuotientRemainder[numRows, numRowsPerFrame];
  numDigits = Ceiling@Log10[numFrames + 2];

  row[i_Integer] := Partition[Join @@ IntegerDigits[
    Normal@data[[numBytesPerRow * (i - 1) + 1 ;; numBytesPerRow * i]],
    2, 8], 3];
  frame[i_Integer] := Image[row /@
      Range[numRowsPerFrame (i - 1) + 1, numRowsPerFrame * i]];

  finalFullRows = row /@ Range[numRowsPerFrame * numFrames + 1, numRows];
  leftoverBits = Join @@ IntegerDigits[
    Normal@data[[-numLeftoverBytes ;;]], 2, 8];
  finalPartialRow = Partition[
    PadRight[leftoverBits, 8 * numBytesPerRow, 1 / 2], 3];
  finalFrameData = Append[finalFullRows, finalPartialRow];
  finalFrame = Image@Join[finalFrameData, ConstantArray[1 / 2,
    {numRowsPerFrame - Length[finalFrameData], (8 / 3) * numBytesPerRow, 3}]];

  Monitor[Do[Image`ImportExportDump`ImageWritePNG[
    "frame_" <> IntegerString[i, 10, numDigits] <> ".png", frame[i]],
    {i, numFrames}], ProgressIndicator[i, {1, numFrames}]];

  Image`ImportExportDump`ImageWritePNG[
    "frame_" <> IntegerString[numFrames + 1, 10, numDigits] <> ".png",
    finalFrame];

  Run[FFmpegExecutablePath,
    "-i", "frame_%0" <> ToString@Ceiling@Log10[numFrames + 1] <> "d.png",
    "-c:v", "libx264", "-preset", "ultrafast",
    "-vf", "scale=1280:720", "-sws_flags", "neighbor", "data.mp4"];

  procInfo = RunProcess[{YouTubeUploadExecutablePath,
    "--title=\"DATA-" <> ToUpperCase@CreateUUID[] <> "\"",
    "data.mp4"}];

  ResetDirectory[];
  DeleteDirectory[tempDir, DeleteContents -> True];

  StringTrim@procInfo["StandardOutput"]];


YouTubeUpload[arg_] := (
  Message[YouTubeUpload::nbarr];
  $Failed);


YouTubeUpload[args___] := (
  Message[YouTubeUpload::argx, YouTubeUpload, Length[{args}]];
  $Failed);


YouTubeRetrieve[videoId_String] := Module[{
  tempDir = CreateDirectory[], videoFile,
  numFrames, rdata, i, lastParts, numPaddedBits, outFile,
  classify = Composition[Round, Mean, Apply[Join],
    ImageData, ImageTake[#, {4, 17}, {4, 17}] &],
  classifyLast = Composition[Round[#, 1 / 2] &, Mean, Apply[Join],
    ImageData, ImageTake[#, {4, 17}, {4, 17}] &]},

  SetDirectory[tempDir];

  RunProcess[{YouTubeDLExecutablePath, videoId}];
  videoFile = FileNames[];
  If[Length[videoFile] != 1,
    Message[YouTubeRetrieve::dlerr, videoId];
    Return[$Failed]];
  videoFile = First[videoFile];

  RunProcess[{FFmpegExecutablePath,
    "-i", FileNameJoin[{tempDir, videoFile}], "frame_%d.png"}];
  numFrames = Max[FromDigits /@ StringTake[FileNames["frame_*.png"], {7, -5}]];

  rdata = Monitor[Join @@ Table[ByteArray[FromDigits[#, 2] & /@
      Partition[Join @@ classify /@ Join @@ ImagePartition[
        First@Image`ImportExportDump`ImageReadPNG[
          "frame_" <> ToString[i] <> ".png"], 20], 8]],
    {i, numFrames - 1}], ProgressIndicator[i, {1, numFrames - 1}]];

  lastParts = Join @@ ImagePartition[First@Image`ImportExportDump`ImageReadPNG[
    "frame_" <> ToString[numFrames] <> ".png"], 20];
  numPaddedBits = LengthWhile[
    Reverse[Join @@ classifyLast /@ lastParts], EqualTo[1 / 2]];
  rdata = Join[rdata, ByteArray[FromDigits[#, 2] & /@ Partition[
    Drop[Join @@ classify /@ lastParts, -numPaddedBits], 8]]];

  ResetDirectory[];
  DeleteDirectory[tempDir, DeleteContents -> True];

  rdata];


YouTubeRetrieve[arg_] := (
  Message[YouTubeRetrieve::nbarr];
  $Failed);


YouTubeRetrieve[args___] := (
  Message[YouTubeRetrieve::argx, YouTubeRetrieve, Length[{args}]];
  $Failed);


End[]; (* `Private` *)
EndPackage[];
