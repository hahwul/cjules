require "./spec_helper"

describe Cjules::Unidiff do
  it "splits a patch into hunks with headers" do
    patch = <<-PATCH
    diff --git a/foo.txt b/foo.txt
    index 0000000..1111111 100644
    --- a/foo.txt
    +++ b/foo.txt
    @@ -0,0 +1,2 @@
    +hello
    +world
    @@ -10,0 +12,1 @@
    +more
    PATCH
    chunks = Cjules::Unidiff.chunks(patch)
    chunks.size.should eq(2)
    chunks[0].lines.first.should start_with("diff --git a/foo.txt b/foo.txt")
    chunks[0].lines.any?(&.starts_with?("@@ -0,0 +1,2 @@")).should be_true
    chunks[1].lines.any?(&.starts_with?("@@ -10,0 +12,1 @@")).should be_true
  end

  it "treats no-@@ sections as one chunk" do
    patch = <<-PATCH
    diff --git a/script.sh b/script.sh
    old mode 100644
    new mode 100755
    PATCH
    chunks = Cjules::Unidiff.chunks(patch)
    chunks.size.should eq(1)
    chunks[0].lines.any?(&.includes?("new mode")).should be_true
  end
end

describe Cjules::Unidiff::Interactive do
  run_select = ->(patch : String, input_s : String) do
    input = IO::Memory.new(input_s)
    output = IO::Memory.new
    display = IO::Memory.new
    {Cjules::Unidiff::Interactive.select(patch, input: input, output: output, display: display), output.to_s, display.to_s}
  end

  it "selects individual hunks with y/n" do
    patch = <<-PATCH
    diff --git a/foo.txt b/foo.txt
    index 0000000..1111111 100644
    --- a/foo.txt
    +++ b/foo.txt
    @@ -0,0 +1,1 @@
    +one
    @@ -2,0 +3,1 @@
    +two
    PATCH
    result, _, _ = run_select.call(patch, "y\nn\n")
    result.selected_chunks.should eq(1)
    result.selected_patch.includes?("+one").should be_true
    result.selected_patch.includes?("+two").should be_false
  end

  it "applies all remaining hunks with a" do
    patch = <<-PATCH
    diff --git a/foo.txt b/foo.txt
    index 0000000..1111111 100644
    --- a/foo.txt
    +++ b/foo.txt
    @@ -0,0 +1,1 @@
    +one
    diff --git a/bar.txt b/bar.txt
    index 0000000..2222222 100644
    --- a/bar.txt
    +++ b/bar.txt
    @@ -0,0 +1,1 @@
    +two
    PATCH
    result, _, _ = run_select.call(patch, "a\n")
    result.selected_chunks.should eq(2)
    result.selected_patch.includes?("diff --git a/foo.txt b/foo.txt").should be_true
    result.selected_patch.includes?("diff --git a/bar.txt b/bar.txt").should be_true
  end

  it "skips all remaining hunks with d" do
    patch = <<-PATCH
    diff --git a/foo.txt b/foo.txt
    index 0000000..1111111 100644
    --- a/foo.txt
    +++ b/foo.txt
    @@ -0,0 +1,1 @@
    +one
    @@ -2,0 +3,1 @@
    +two
    PATCH
    result, _, _ = run_select.call(patch, "d\n")
    result.selected_patch.empty?.should be_true
    result.quit_early?.should be_false
    result.skipped_chunks.should eq(2)
  end

  it "quits early with q" do
    patch = <<-PATCH
    diff --git a/foo.txt b/foo.txt
    index 0000000..1111111 100644
    --- a/foo.txt
    +++ b/foo.txt
    @@ -0,0 +1,1 @@
    +one
    PATCH
    result, _, _ = run_select.call(patch, "q\n")
    result.selected_patch.empty?.should be_true
    result.quit_early?.should be_true
  end
end
